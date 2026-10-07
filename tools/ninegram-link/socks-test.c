#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

#pragma comment(lib, "ws2_32.lib")

int main(int argc, char **argv)
{
    WSADATA data;
    WSAStartup(MAKEWORD(2, 2), &data);
    if (!LoadLibraryA("ninegram-socks.dll")) {
        printf("load failed %lu\n", GetLastError());
        return 1;
    }
    struct addrinfo hints;
    struct addrinfo *result = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = (argc > 1 && argv[1][0] == '6') ? AF_INET6 : AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (argc > 1 && argv[1][0] == '6') {
        struct sockaddr_in6 dest;
        memset(&dest, 0, sizeof(dest));
        dest.sin6_family = AF_INET6;
        dest.sin6_port = htons(443);
        inet_pton(AF_INET6, "2001:4860:4860::8888", &dest.sin6_addr);
        result = (struct addrinfo *)calloc(1, sizeof(*result));
        result->ai_addr = (struct sockaddr *)malloc(sizeof(dest));
        memcpy(result->ai_addr, &dest, sizeof(dest));
        result->ai_addrlen = sizeof(dest);
    } else if (getaddrinfo("api.ipify.org", "80", &hints, &result) != 0 || !result) {
        printf("dns failed\n");
        return 1;
    }
    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    u_long nonblock = 1;
    ioctlsocket(s, FIONBIO, &nonblock);
    int rc = connect(s, result->ai_addr, (int)result->ai_addrlen);
    if (rc != 0) {
        printf("connect failed %d\n", WSAGetLastError());
        return 1;
    }
    u_long blocking = 0;
    ioctlsocket(s, FIONBIO, &blocking);
    const char *request = "GET / HTTP/1.0\r\nHost: api.ipify.org\r\nConnection: close\r\n\r\n";
    send(s, request, (int)strlen(request), 0);
    char buf[1024];
    int total = 0;
    for (;;) {
        int n = recv(s, buf + total, (int)sizeof(buf) - total - 1, 0);
        if (n <= 0) {
            break;
        }
        total += n;
        if (total > 900) {
            break;
        }
    }
    buf[total] = 0;
    printf("%s\n", buf);
    return 0;
}
