using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Http;
using ImageMagick;

try { await Run(args); }
catch (Exception ex)
{
    // Full exception/inner stack for test diagnostics, without Windows unhandled-error UI.
    Console.Error.WriteLine(ex);
    Environment.ExitCode = 1;
}

static async Task Run(string[] args)
{
    var output = Path.GetFullPath(args.Single());
    Directory.CreateDirectory(output);
    using var image = new MagickImage(MagickColors.CornflowerBlue, 64, 48);
    var png = image.ToByteArray(MagickFormat.Png);
    var jpeg = image.ToByteArray(MagickFormat.Jpeg);
    var fixtures = new Dictionary<string, byte[]>
    {
        ["valid.png"] = png,
        ["valid.jpg"] = jpeg,
        ["text.jpg"] = Encoding.UTF8.GetBytes("This is not an image"),
        ["signature.png"] = png[..8],
        ["signature.jpg"] = jpeg[..3],
        ["fake-header.jpg"] = [..jpeg[..3], ..Encoding.UTF8.GetBytes("not a JPEG image"), 0xff, 0xd9],
        ["fake-header.png"] = [..png[..8], ..Encoding.UTF8.GetBytes("not a PNG image")],
        ["truncated.png"] = png[..(png.Length / 2)],
        ["truncated.jpg"] = jpeg[..(jpeg.Length / 2)],
        ["missing-end.png"] = png[..^12],
        ["missing-end.jpg"] = jpeg[..^2],
        ["oversize.png"] = new byte[DeliveryEvidenceImage.MaxFileSize + 1],
        ["max-size.png"] = new byte[DeliveryEvidenceImage.MaxFileSize],
        ["wide.png"] = MakePng(8193, 1),
        ["pixels.png"] = MakePng(4001, 4000),
        ["bad-idat.png"] = DamageChunk(png, "IDAT"),
        ["bad-entropy.jpg"] = DamageJpeg(jpeg),
        ["animated.png"] = AddAnimation(png),
        ["unsupported.gif"] = Convert.FromBase64String("R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")
    };
    // A valid PNG at exactly 5 MB: a legal ancillary chunk, not trailing garbage.
    fixtures["max-size.png"] = InsertChunk(png, "qaTa", new byte[DeliveryEvidenceImage.MaxFileSize - png.Length - 12]);
    foreach (var (name, bytes) in fixtures) await File.WriteAllBytesAsync(Path.Combine(output, name), bytes);
    var checks = 0;
    foreach (var (name, bytes) in fixtures)
    {
        var valid = name is "valid.png" or "valid.jpg" or "max-size.png";
        try
        {
            using var stream = new MemoryStream(bytes);
            var result = await DeliveryEvidenceImage.ReadAsync(new FormFile(stream, 0, bytes.Length, "File", "misleading.txt"), default);
            if (!valid) throw new Exception("Accepted invalid fixture " + name);
            if (!result.Bytes.SequenceEqual(bytes)) throw new Exception("Unexpected evidence byte changes");
        }
        catch (EvidenceImageException ex) when (!valid && ex.StatusCode is 400 or 415) { }
        catch (EvidenceImageException ex) { throw new Exception("Valid fixture failed: " + name + ": " + ex.InnerException?.Message, ex); }
        checks++;
    }
    // A lying Length must not bypass the byte limit, including while streaming.
    try
    {
        await DeliveryEvidenceImage.ReadAsync(new LyingFile(fixtures["oversize.png"]), default);
        throw new Exception("Unbounded input accepted");
    }
    catch (EvidenceImageException ex) when (ex.StatusCode == 400 && ex.Message.Contains("5 MB")) { checks++; }
    using (var cts = new CancellationTokenSource())
    {
        cts.Cancel();
        try
        {
            await DeliveryEvidenceImage.ReadAsync(new LyingFile(png), cts.Token);
            throw new Exception("Cancellation ignored");
        }
        catch (OperationCanceledException) { checks++; }
    }
    // Semaphore/resources remain usable after malformed and cancelled requests.
    await Task.WhenAll(Enumerable.Range(0, 6).Select(async _ =>
    {
        using var stream = new MemoryStream(jpeg);
        await DeliveryEvidenceImage.ReadAsync(new FormFile(stream, 0, jpeg.Length, "File", "wrong.png"), default);
    }));
    checks++;
    Console.WriteLine($"Image checks passed: {checks}");
}

static byte[] MakePng(int width, int height)
{
    using var result = new MemoryStream();
    result.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
    var header = new byte[13];
    BinaryPrimitives.WriteInt32BigEndian(header, width);
    BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), height);
    header[8] = 8; header[9] = 2;
    result.Write(Chunk("IHDR", header));
    using var compressed = new MemoryStream();
    using (var zlib = new ZLibStream(compressed, CompressionLevel.SmallestSize, leaveOpen: true))
    {
        var row = new byte[1 + 3 * width];
        for (var y = 0; y < height; y++) zlib.Write(row);
    }
    result.Write(Chunk("IDAT", compressed.ToArray()));
    result.Write(Chunk("IEND", []));
    return result.ToArray();
}
static byte[] Chunk(string type, byte[] data)
{
    var chunk = new byte[data.Length + 12];
    BinaryPrimitives.WriteInt32BigEndian(chunk, data.Length);
    Encoding.ASCII.GetBytes(type).CopyTo(chunk, 4);
    data.CopyTo(chunk, 8);
    uint crc = 0xffffffff;
    foreach (var b in chunk.AsSpan(4, data.Length + 4))
    {
        crc ^= b;
        for (var i = 0; i < 8; i++) crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320u : 0);
    }
    BinaryPrimitives.WriteUInt32BigEndian(chunk.AsSpan(chunk.Length - 4), ~crc);
    return chunk;
}
static byte[] InsertChunk(byte[] png, string type, byte[] data) => [..png[..33], ..Chunk(type, data), ..png[33..]];
static byte[] AddAnimation(byte[] png)
{
    var data = new byte[8]; data[3] = 1;
    return InsertChunk(png, "acTL", data);
}
static byte[] DamageChunk(byte[] png, string type)
{
    var copy = png.ToArray();
    for (var offset = 8; offset < copy.Length;)
    {
        var length = BinaryPrimitives.ReadInt32BigEndian(copy.AsSpan(offset));
        if (Encoding.ASCII.GetString(copy, offset + 4, 4) == type)
        {
            copy[offset + 8] ^= 0xff;
            return copy;
        }
        offset += length + 12;
    }
    throw new Exception("Fixture chunk not found");
}
static byte[] DamageJpeg(byte[] jpeg)
{
    // Preserve SOI/header/EOI but remove most entropy-coded scan data.
    for (var i = 2; i < jpeg.Length - 4; i++)
        if (jpeg[i] == 0xff && jpeg[i + 1] == 0xda)
        {
            var start = i + 2 + BinaryPrimitives.ReadUInt16BigEndian(jpeg.AsSpan(i + 2));
            return [..jpeg[..(start + 2)], 0xff, 0xd9];
        }
    throw new Exception("Fixture scan not found");
}

sealed class LyingFile(byte[] bytes) : IFormFile
{
    public string ContentType => "image/png";
    public string ContentDisposition => "";
    public IHeaderDictionary Headers { get; set; } = new HeaderDictionary();
    public long Length => 1;
    public string Name => "File";
    public string FileName => "fake.png";
    public Stream OpenReadStream() => new MemoryStream(bytes);
    public void CopyTo(Stream target) => throw new NotSupportedException();
    public Task CopyToAsync(Stream target, CancellationToken cancellationToken = default) => throw new NotSupportedException();
}
