using System.Data.Common;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Services;

public sealed class SqlResultContractException(string reason) : Exception(reason);

// These commands promise exactly one result set and one row. Never scan past
// an unexpected set: it may be a SELECT accidentally added to a trigger/proc.
public static class SqlResult
{
    public const string UnknownWriteMessage =
        "Không đọc được kết quả xử lý. Hãy tải lại để kiểm tra trạng thái.";

    public static async Task<T> ReadSingleAsync<T>(
        DbDataReader reader, string[] columns, Func<Row, T> project,
        CancellationToken cancellationToken = default, Func<T>? whenEmpty = null)
    {
        if (reader.FieldCount != columns.Length ||
            columns.Any(name => Enumerable.Range(0, reader.FieldCount)
                .Count(i => string.Equals(reader.GetName(i), name, StringComparison.Ordinal)) != 1))
            throw new SqlResultContractException("Unexpected result columns; expected: " + string.Join(", ", columns));

        if (!await reader.ReadAsync(cancellationToken))
        {
            if (await reader.NextResultAsync(cancellationToken))
                throw new SqlResultContractException("Unexpected additional result set after empty result");
            if (whenEmpty is not null) return whenEmpty();
            throw new SqlResultContractException("Expected one result row, received none");
        }

        var result = project(new Row(reader));
        if (await reader.ReadAsync(cancellationToken))
            throw new SqlResultContractException("Expected one result row, received multiple rows");
        // Consume through command completion, including errors after the row.
        if (await reader.NextResultAsync(cancellationToken))
            throw new SqlResultContractException("Unexpected additional result set");
        return result;
    }

    public sealed class Row(DbDataReader reader)
    {
        public T Required<T>(string column)
        {
            var value = reader.GetValue(reader.GetOrdinal(column));
            if (value is not T typed)
                throw new SqlResultContractException("Required column " + column + " is NULL or has an unexpected SQL type");
            return typed;
        }

        public long Id(string column)
        {
            var id = Required<long>(column);
            if (id <= 0) throw new SqlResultContractException("Required ID " + column + " is not positive");
            return id;
        }

        public int IntId(string column)
        {
            var id = Required<int>(column);
            if (id <= 0) throw new SqlResultContractException("Required ID " + column + " is not positive");
            return id;
        }

        public byte[] Version(string column = "Version")
        {
            var value = Required<byte[]>(column);
            if (value.Length != 8) throw new SqlResultContractException("Required rowversion " + column + " must contain 8 bytes");
            return value;
        }

        public decimal NonNegative(string column)
        {
            var value = Required<decimal>(column);
            if (value < 0) throw new SqlResultContractException("Required value " + column + " is negative");
            return value;
        }

        public string Text(string column)
        {
            var value = Required<string>(column);
            if (string.IsNullOrWhiteSpace(value)) throw new SqlResultContractException("Required text " + column + " is empty");
            return value;
        }

        public string JsonArray(string column)
        {
            var value = Text(column);
            try
            {
                using var json = JsonDocument.Parse(value);
                if (json.RootElement.ValueKind == JsonValueKind.Array) return value;
            }
            catch (JsonException) { /* Never log result contents. */ }
            throw new SqlResultContractException("Required JSON array " + column + " is invalid");
        }
    }

    public static ObjectResult Failure(ILogger logger, string endpoint, object objectId,
        string reason, bool writeMayHaveRun)
    {
        // Only controlled reasons/SQL metadata; never SQL payloads or exception
        // messages (constraint errors can contain sensitive record values).
        logger.LogError("SQL result failure at {Endpoint}; object {ObjectId}; write attempted {WriteAttempted}; reason {Reason}",
            endpoint, objectId, writeMayHaveRun, reason);
        return new ObjectResult(new
        {
            message = writeMayHaveRun ? UnknownWriteMessage : "Không đọc được dữ liệu xử lý. Hãy tải lại và thử lại sau.",
            code = "SQL_RESULT_UNAVAILABLE",
            resultUnknown = writeMayHaveRun
        }) { StatusCode = StatusCodes.Status500InternalServerError };
    }

    public static string ErrorReason(SqlException error) =>
        $"SQL error {error.Number}; procedure {error.Procedure}; line {error.LineNumber}; state {error.State}";
}
