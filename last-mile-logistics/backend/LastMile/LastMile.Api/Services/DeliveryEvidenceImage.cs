using System.Buffers.Binary;
using ImageMagick;

namespace LastMile.Api.Services;

public sealed class EvidenceImageException(int statusCode, string message, Exception? inner = null) : Exception(message, inner)
{
    public int StatusCode { get; } = statusCode;
}

public sealed record DeliveryEvidenceImage(byte[] Bytes, string Extension)
{
    public const int MaxFileSize = 5 * 1024 * 1024;
    public const int MaxDimension = 8192;
    public const long MaxPixels = 16_000_000;

    // At most two bounded decodes per process, independent of SQL transactions.
    private static readonly SemaphoreSlim DecodeSlots = new(2);

    static DeliveryEvidenceImage()
    {
        // Process-wide native pixel-cache budgets. Never spill upload data to disk.
        ResourceLimits.Width = MaxDimension;
        ResourceLimits.Height = MaxDimension;
        ResourceLimits.Area = (ulong)MaxPixels;
        ResourceLimits.Memory = 256 * 1024 * 1024;
        ResourceLimits.MaxMemoryRequest = 128 * 1024 * 1024;
        ResourceLimits.MaxProfileSize = MaxFileSize;
        ResourceLimits.Disk = 0;
        ResourceLimits.Thread = 2;
        // Read can briefly hold both the ping image and its replacement cache.
        ResourceLimits.ListLength = 4;
    }

    public static async Task<DeliveryEvidenceImage> ReadAsync(IFormFile file, CancellationToken cancellationToken)
    {
        if (file.Length <= 0 || file.Length > MaxFileSize) throw SizeError();

        await DecodeSlots.WaitAsync(cancellationToken);
        try
        {
            await using var source = file.OpenReadStream();
            using var buffer = new MemoryStream();
            var block = new byte[81920];
            // Do not trust Length alone, and never buffer an unbounded stream.
            while (true)
            {
                var count = await source.ReadAsync(block.AsMemory(0,
                    (int)Math.Min(block.Length, MaxFileSize + 1L - buffer.Length)), cancellationToken);
                if (count == 0) break;
                buffer.Write(block, 0, count);
                if (buffer.Length > MaxFileSize) throw SizeError();
            }
            if (buffer.Length == 0) throw SizeError();
            var bytes = buffer.ToArray();

            // Signature only selects one of two decoders; it never validates an image.
            // Explicit Format avoids invoking any other ImageMagick coder/delegate.
            var format = bytes.AsSpan().StartsWith(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 })
                ? MagickFormat.Png
                : bytes.Length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff
                    ? MagickFormat.Jpeg : throw FormatError();
            var extension = format == MagickFormat.Png ? ".png" : ".jpg";
            var settings = new MagickReadSettings { Format = format, FrameCount = 1 };
            // Reject animation and incomplete containers before any native parsing.
            ValidateContainer(bytes, extension);

            // Ping reads dimensions without allocating the full pixel cache.
            using var image = new MagickImage();
            var warned = false;
            image.Warning += (_, _) => warned = true;
            image.Ping(bytes, settings);
            if (warned) throw ContentError();
            if (image.Width == 0 || image.Height == 0 || image.Width > MaxDimension
                || image.Height > MaxDimension || (ulong)image.Width * image.Height > MaxPixels)
            {
                throw DimensionError();
            }

            cancellationToken.ThrowIfCancellationRequested();
            image.Read(bytes, settings);
            // libjpeg can recover truncated scans with a warning; reject those too.
            if (warned) throw ContentError();
            cancellationToken.ThrowIfCancellationRequested();
            return new DeliveryEvidenceImage(bytes, extension);
        }
        catch (MagickResourceLimitErrorException ex) { throw DimensionError(ex); }
        catch (Exception ex) when (ex is MagickException or InvalidDataException or EndOfStreamException)
        {
            throw ContentError(ex);
        }
        finally { DecodeSlots.Release(); }
    }

    private static void ValidateContainer(ReadOnlySpan<byte> bytes, string extension)
    {
        if (extension == ".jpg")
        {
            if (bytes.Length < 4 || bytes[^2] != 0xff || bytes[^1] != 0xd9) throw ContentError();
            return;
        }

        var offset = 8; // PNG signature already checked; validate the complete container.
        while (offset <= bytes.Length - 12)
        {
            var length = BinaryPrimitives.ReadUInt32BigEndian(bytes[offset..]);
            if (length > bytes.Length - offset - 12) throw ContentError();
            var type = bytes.Slice(offset + 4, 4);
            if (type.SequenceEqual("acTL"u8))
                throw new EvidenceImageException(415, "Chỉ chấp nhận ảnh PNG hoặc JPEG tĩnh, không có nhiều khung hình.");
            offset += (int)length + 12;
            if (type.SequenceEqual("IEND"u8))
            {
                if (length != 0 || offset != bytes.Length) throw ContentError();
                return;
            }
        }
        throw ContentError();
    }

    private static EvidenceImageException SizeError() => new(400, "Ảnh phải có dung lượng lớn hơn 0 và tối đa 5 MB.");
    private static EvidenceImageException DimensionError(Exception? inner = null) => new(400, "Ảnh vượt giới hạn xử lý: tối đa 8.192 pixel mỗi chiều, tổng cộng 16 triệu pixel. Hãy giảm kích thước ảnh.", inner);
    private static EvidenceImageException FormatError() => new(415, "Chỉ chấp nhận ảnh JPEG hoặc PNG.");
    private static EvidenceImageException ContentError(Exception? inner = null) => new(400, "Ảnh PNG hoặc JPEG bị hỏng, bị cắt cụt hoặc không giải mã được. Hãy chọn ảnh khác.", inner);
}
