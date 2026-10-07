#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdint.h>
#include <stdio.h>

#pragma comment(lib, "ws2_32.lib")

#define SOCKS_PORT 11080

typedef int (WSAAPI *connect_fn)(SOCKET, const struct sockaddr *, int);
typedef int (WSAAPI *wsaconnect_fn)(SOCKET, const struct sockaddr *, int, LPWSABUF, LPWSABUF, LPQOS, LPQOS);

static connect_fn g_connect = NULL;
static wsaconnect_fn g_wsaconnect = NULL;

static void log_line(const char *text)
{
    wchar_t dir[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"USERPROFILE", dir, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) {
        return;
    }
    wchar_t path[MAX_PATH];
    _snwprintf(path, MAX_PATH, L"%s\\.ninegram-link\\socks.log", dir);
    FILE *file = _wfopen(path, L"a");
    if (!file) {
        return;
    }
    fprintf(file, "%s\n", text);
    fclose(file);
}

static int insn_len(const unsigned char *p)
{
    if (p[0] == 0x40 && p[1] == 0x53) return 2;
    if (p[0] == 0x55) return 1;
    if (p[0] == 0x57) return 1;
    if (p[0] == 0x41 && p[1] >= 0x54 && p[1] <= 0x57) return 2;
    if (p[0] == 0x48 && p[1] == 0x81 && p[2] == 0xEC) return 7;
    if (p[0] == 0x48 && p[1] == 0x83 && p[2] == 0xEC) return 4;
    if (p[0] == 0x48 && p[1] == 0x89 && p[3] == 0x24 && (p[2] == 0x5C || p[2] == 0x6C || p[2] == 0x74)) return 5;
    return 0;
}

static int steal_len(const unsigned char *code)
{
    int total = 0;
    while (total < 14) {
        int n = insn_len(code + total);
        if (n <= 0 || total + n > 32) {
            return 0;
        }
        total += n;
    }
    return total;
}

static void write_jump(unsigned char *at, void *target)
{
    at[0] = 0xFF;
    at[1] = 0x25;
    *(int32_t *)(at + 2) = 0;
    *(uint64_t *)(at + 6) = (uint64_t)target;
}

static void *hook_function(void *target, void *hook)
{
    unsigned char *code = (unsigned char *)target;
    int n = steal_len(code);
    if (n < 14) {
        return NULL;
    }
    unsigned char *tramp = (unsigned char *)VirtualAlloc(NULL, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!tramp) {
        return NULL;
    }
    memcpy(tramp, code, n);
    write_jump(tramp + n, code + n);
    DWORD old = 0;
    if (!VirtualProtect(code, n, PAGE_EXECUTE_READWRITE, &old)) {
        return NULL;
    }
    write_jump(code, hook);
    for (int i = 14; i < n; i++) {
        code[i] = 0x90;
    }
    VirtualProtect(code, n, old, &old);
    FlushInstructionCache(GetCurrentProcess(), code, n);
    return tramp;
}

static int send_all(SOCKET s, const void *data, int len)
{
    const char *p = (const char *)data;
    int left = len;
    while (left > 0) {
        int n = send(s, p, left, 0);
        if (n <= 0) {
            return -1;
        }
        p += n;
        left -= n;
    }
    return 0;
}

static int recv_all(SOCKET s, void *data, int len)
{
    char *p = (char *)data;
    int left = len;
    while (left > 0) {
        int n = recv(s, p, left, 0);
        if (n <= 0) {
            return -1;
        }
        p += n;
        left -= n;
    }
    return 0;
}

static int is_local(const struct sockaddr *name)
{
    if (name->sa_family == AF_INET) {
        const struct sockaddr_in *in = (const struct sockaddr_in *)name;
        return (ntohl(in->sin_addr.s_addr) >> 24) == 127;
    }
    if (name->sa_family == AF_INET6) {
        const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)name;
        return IN6_IS_ADDR_LOOPBACK(&in6->sin6_addr);
    }
    return 1;
}

static int proxy_connect(SOCKET s, const struct sockaddr *name)
{
    u_long blocking = 0;
    ioctlsocket(s, FIONBIO, &blocking);
    DWORD timeout = 15000;
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout, sizeof(timeout));

    WSAPROTOCOL_INFOW info;
    int info_len = sizeof(info);
    int family = AF_INET;
    if (getsockopt(s, SOL_SOCKET, SO_PROTOCOL_INFOW, (char *)&info, &info_len) == 0) {
        family = info.iAddressFamily;
    }
    if (family == AF_INET6) {
        struct sockaddr_in6 proxy6;
        memset(&proxy6, 0, sizeof(proxy6));
        proxy6.sin6_family = AF_INET6;
        proxy6.sin6_port = htons(SOCKS_PORT);
        proxy6.sin6_addr = in6addr_loopback;
        if (g_connect(s, (struct sockaddr *)&proxy6, sizeof(proxy6)) != 0) {
            char buf[64];
            sprintf(buf, "socks v6 dial failed %d", WSAGetLastError());
            log_line(buf);
            return -1;
        }
    } else {
        struct sockaddr_in proxy;
        memset(&proxy, 0, sizeof(proxy));
        proxy.sin_family = AF_INET;
        proxy.sin_port = htons(SOCKS_PORT);
        proxy.sin_addr.s_addr = htonl(0x7F000001);
        if (g_connect(s, (struct sockaddr *)&proxy, sizeof(proxy)) != 0) {
            char buf[64];
            sprintf(buf, "socks v4 dial failed %d", WSAGetLastError());
            log_line(buf);
            return -1;
        }
    }

    unsigned char greet[3] = { 5, 1, 0 };
    unsigned char reply[2];
    if (send_all(s, greet, 3) || recv_all(s, reply, 2) || reply[0] != 5 || reply[1] != 0) {
        return -1;
    }

    unsigned char req[22];
    int req_len = 0;
    req[0] = 5;
    req[1] = 1;
    req[2] = 0;
    if (name->sa_family == AF_INET) {
        const struct sockaddr_in *in = (const struct sockaddr_in *)name;
        req[3] = 1;
        memcpy(req + 4, &in->sin_addr, 4);
        memcpy(req + 8, &in->sin_port, 2);
        req_len = 10;
    } else if (name->sa_family == AF_INET6) {
        const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)name;
        req[3] = 4;
        memcpy(req + 4, &in6->sin6_addr, 16);
        memcpy(req + 20, &in6->sin6_port, 2);
        req_len = 22;
    } else {
        return -1;
    }
    if (send_all(s, req, req_len)) {
        return -1;
    }
    unsigned char head[4];
    if (recv_all(s, head, 4) || head[1] != 0) {
        return -1;
    }
    int rest = 0;
    if (head[3] == 1) rest = 6;
    else if (head[3] == 4) rest = 18;
    else if (head[3] == 3) {
        unsigned char n = 0;
        if (recv_all(s, &n, 1)) return -1;
        rest = n + 2;
    } else {
        return -1;
    }
    unsigned char skip[260];
    if (rest < 0 || rest > (int)sizeof(skip) || (rest > 0 && recv_all(s, skip, rest))) {
        return -1;
    }
    DWORD none = 0;
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (char *)&none, sizeof(none));
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (char *)&none, sizeof(none));

    u_long nonblock = 1;
    ioctlsocket(s, FIONBIO, &nonblock);
    return 0;
}

static int WSAAPI hooked_connect(SOCKET s, const struct sockaddr *name, int namelen)
{
    int kind = 0;
    int kind_len = sizeof(kind);
    if (!name || is_local(name) || getsockopt(s, SOL_SOCKET, SO_TYPE, (char *)&kind, &kind_len) != 0 || kind != SOCK_STREAM) {
        return g_connect(s, name, namelen);
    }
    if (proxy_connect(s, name) != 0) {
        log_line("socks handshake failed");
        WSASetLastError(WSAECONNREFUSED);
        return SOCKET_ERROR;
    }
    return 0;
}

static int WSAAPI hooked_wsaconnect(SOCKET s, const struct sockaddr *name, int namelen, LPWSABUF caller, LPWSABUF callee, LPQOS send_qos, LPQOS recv_qos)
{
    (void)caller;
    (void)callee;
    (void)send_qos;
    (void)recv_qos;
    return hooked_connect(s, name, namelen);
}

static int should_hook(void)
{
    wchar_t path[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) {
        return 0;
    }
    const wchar_t *slash = wcsrchr(path, L'\\');
    const wchar_t *name = slash ? slash + 1 : path;
    if (_wcsicmp(name, L"AyuGram-ninegram.exe") == 0) {
        return 1;
    }
    wchar_t flag[8];
    return GetEnvironmentVariableW(L"NINEGRAM_SOCKS", flag, 8) > 0;
}

static int install_hooks(void)
{
    HMODULE ws = GetModuleHandleW(L"ws2_32.dll");
    if (!ws) {
        ws = LoadLibraryW(L"ws2_32.dll");
    }
    if (!ws) {
        return 0;
    }
    void *connect_ptr = (void *)GetProcAddress(ws, "connect");
    void *wsa_ptr = (void *)GetProcAddress(ws, "WSAConnect");
    if (!connect_ptr || !wsa_ptr) {
        return 0;
    }
    g_connect = (connect_fn)hook_function(connect_ptr, (void *)hooked_connect);
    g_wsaconnect = (wsaconnect_fn)hook_function(wsa_ptr, (void *)hooked_wsaconnect);
    if (!g_connect || !g_wsaconnect) {
        log_line("hook install failed");
        return 0;
    }
    log_line("socks hook installed");
    return 1;
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved)
{
    (void)module;
    (void)reserved;
    if (reason != DLL_PROCESS_ATTACH) {
        return TRUE;
    }
    DisableThreadLibraryCalls(module);
    if (!should_hook()) {
        return TRUE;
    }
    return install_hooks() ? TRUE : FALSE;
}
