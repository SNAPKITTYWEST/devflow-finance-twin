using System;
using System.Runtime.InteropServices;
using System.Text;

namespace LedgerGateway
{
    [StructLayout(LayoutKind.Sequential, Pack = 1, CharSet = CharSet.Ansi)]
    public struct LedgerReverseRequestBlock
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 3)]
        public string Company;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 8)]
        public string LedgerDate; // YYYYMMDD

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 9)]
        public string LedgerSeq;  // zero-padded

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 10)]
        public string UserId;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 4)]
        public string ReasonCode;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 8)]
        public string Channel;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 8)]
        public string RailCode;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 78)]
        public byte[] Reserved;

        public static LedgerReverseRequestBlock FromDomain(
            string company,
            DateTime ledgerDate,
            long ledgerSeq,
            string userId,
            string reasonCode,
            string channel,
            string railCode)
        {
            return new LedgerReverseRequestBlock
            {
                Company = company.PadRight(3).Substring(0, 3),
                LedgerDate = ledgerDate.ToString("yyyyMMdd"),
                LedgerSeq = ledgerSeq.ToString().PadLeft(9, '0'),
                UserId = (userId ?? string.Empty).PadRight(10).Substring(0, 10),
                ReasonCode = (reasonCode ?? string.Empty).PadRight(4).Substring(0, 4),
                Channel = (channel ?? string.Empty).PadRight(8).Substring(0, 8),
                RailCode = (railCode ?? string.Empty).PadRight(8).Substring(0, 8),
                Reserved = new byte[78]
            };
        }

        public byte[] ToBytes()
        {
            int size = Marshal.SizeOf(typeof(LedgerReverseRequestBlock));
            var buffer = new byte[size];
            IntPtr ptr = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(this, ptr, false);
                Marshal.Copy(ptr, buffer, 0, size);
                return buffer;
            }
            finally
            {
                Marshal.FreeHGlobal(ptr);
            }
        }

        public static LedgerReverseRequestBlock FromBytes(byte[] buffer)
        {
            int size = Marshal.SizeOf(typeof(LedgerReverseRequestBlock));
            if (buffer.Length < size)
                throw new ArgumentException("Buffer too small for request block.");

            IntPtr ptr = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.Copy(buffer, 0, ptr, size);
                return (LedgerReverseRequestBlock)Marshal.PtrToStructure(
                    ptr, typeof(LedgerReverseRequestBlock));
            }
            finally
            {
                Marshal.FreeHGlobal(ptr);
            }
        }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1, CharSet = CharSet.Ansi)]
    public struct LedgerReverseResponseBlock
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1)]
        public string Success; // 'Y' or 'N'

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 8)]
        public string ErrorCode;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string ErrorMsg;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 9)]
        public string NewLedgerSeq;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 30)]
        public byte[] Reserved;

        public byte[] ToBytes()
        {
            int size = Marshal.SizeOf(typeof(LedgerReverseResponseBlock));
            var buffer = new byte[size];
            IntPtr ptr = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(this, ptr, false);
                Marshal.Copy(ptr, buffer, 0, size);
                return buffer;
            }
            finally
            {
                Marshal.FreeHGlobal(ptr);
            }
        }

        public static LedgerReverseResponseBlock FromBytes(byte[] buffer)
        {
            int size = Marshal.SizeOf(typeof(LedgerReverseResponseBlock));
            if (buffer.Length < size)
                throw new ArgumentException("Buffer too small for response block.");

            IntPtr ptr = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.Copy(buffer, 0, ptr, size);
                return (LedgerReverseResponseBlock)Marshal.PtrToStructure(
                    ptr, typeof(LedgerReverseResponseBlock));
            }
            finally
            {
                Marshal.FreeHGlobal(ptr);
            }
        }

        public bool IsSuccess() => Success == "Y";

        public long GetNewLedgerSeq()
        {
            if (string.IsNullOrWhiteSpace(NewLedgerSeq))
                return 0;
            if (long.TryParse(NewLedgerSeq.Trim(), out var v))
                return v;
            return 0;
        }
    }

    public static class LedgerGatewayClient
    {
        // This is the boundary: send 128-byte request, receive 128-byte response.
        // Wire could be TCP, MQ, data queue, etc. Here we just show the call shape.
        public static LedgerReverseResponseBlock CallGateway(
            Func<byte[], byte[]> transport,
            LedgerReverseRequestBlock request)
        {
            var reqBytes = request.ToBytes();
            var rspBytes = transport(reqBytes); // must return exactly 128 bytes
            return LedgerReverseResponseBlock.FromBytes(rspBytes);
        }
    }
}
