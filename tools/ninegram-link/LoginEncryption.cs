using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal static class LoginEncryption
{
    private static readonly object KeyLock = new object();
    private static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ninegram-link");

    internal static void ExportPublicKey(string path, string keyDirectory = null)
    {
        using (var rsa = LoadKey(keyDirectory))
        {
            File.WriteAllText(path, Convert.ToBase64String(rsa.ExportRSAPublicKey()));
        }
    }

    internal static string Decrypt(string value, string keyDirectory = null)
    {
        // Existing phone builds remain compatible while the encrypted IPA is installed.
        if (!value.StartsWith("ng1:", StringComparison.Ordinal))
        {
            return value;
        }
        using (var doc = JsonDocument.Parse(Convert.FromBase64String(value.Substring(4))))
        using (var rsa = LoadKey(keyDirectory))
        {
            var obj = doc.RootElement;
            var key = rsa.Decrypt(Convert.FromBase64String(obj.GetProperty("key").GetString()), RSAEncryptionPadding.OaepSHA256);
            var ciphertext = Convert.FromBase64String(obj.GetProperty("ciphertext").GetString());
            var plaintext = new byte[ciphertext.Length];
            try
            {
                using (var aes = new AesGcm(key, 16))
                {
                    aes.Decrypt(Convert.FromBase64String(obj.GetProperty("nonce").GetString()), ciphertext,
                        Convert.FromBase64String(obj.GetProperty("tag").GetString()), plaintext);
                }
                return Encoding.UTF8.GetString(plaintext);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(key);
                CryptographicOperations.ZeroMemory(plaintext);
            }
        }
    }

    private static RSA LoadKey(string directory = null)
    {
        lock (KeyLock)
        {
            directory = directory ?? Root;
            Directory.CreateDirectory(directory);
            var privateKeyPath = Path.Combine(directory, "link-private-key.dpapi");
            var rsa = RSA.Create();
            try
            {
                if (!File.Exists(privateKeyPath))
                {
                    rsa.KeySize = 3072;
                    var privateKey = rsa.ExportPkcs8PrivateKey();
                    try
                    {
                        var protectedKey = Protect(privateKey, decrypt: false);
                        using (var file = new FileStream(privateKeyPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        {
                            file.Write(protectedKey);
                        }
                    }
                    finally
                    {
                        CryptographicOperations.ZeroMemory(privateKey);
                    }
                }
                else
                {
                    var privateKey = Protect(File.ReadAllBytes(privateKeyPath), decrypt: true);
                    try
                    {
                        rsa.ImportPkcs8PrivateKey(privateKey, out _);
                    }
                    finally
                    {
                        CryptographicOperations.ZeroMemory(privateKey);
                    }
                }
                return rsa;
            }
            catch
            {
                rsa.Dispose();
                throw;
            }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DataBlob { public int Length; public IntPtr Data; }

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CryptProtectData(ref DataBlob input, string description, IntPtr entropy, IntPtr reserved, IntPtr prompt, uint flags, out DataBlob output);
    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CryptUnprotectData(ref DataBlob input, IntPtr description, IntPtr entropy, IntPtr reserved, IntPtr prompt, uint flags, out DataBlob output);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr data);

    private static byte[] Protect(byte[] value, bool decrypt)
    {
        var input = new DataBlob { Length = value.Length, Data = Marshal.AllocHGlobal(value.Length) };
        var output = new DataBlob();
        try
        {
            Marshal.Copy(value, 0, input.Data, value.Length);
            var success = decrypt
                ? CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output)
                : CryptProtectData(ref input, "Ninegram device pairing", IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output);
            if (!success) { throw new Win32Exception(Marshal.GetLastWin32Error()); }
            var result = new byte[output.Length];
            Marshal.Copy(output.Data, result, 0, result.Length);
            return result;
        }
        finally
        {
            for (var i = 0; i < input.Length; i++) { Marshal.WriteByte(input.Data, i, 0); }
            Marshal.FreeHGlobal(input.Data);
            if (output.Data != IntPtr.Zero)
            {
                for (var i = 0; i < output.Length; i++) { Marshal.WriteByte(output.Data, i, 0); }
                LocalFree(output.Data);
            }
        }
    }
}
