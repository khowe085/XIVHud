FROM mcr.microsoft.com/devcontainers/base:alpine-3.20

RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 luacheck build-base curl unzip github-cli \
    && ln -sf /usr/bin/lua5.1 /usr/local/bin/lua \
    && luarocks-5.1 install busted LUA_INCDIR=/usr/include \
    && curl -fsSL "https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-linux-x86_64-musl.zip" \
        -o /tmp/stylua.zip \
    && unzip /tmp/stylua.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/stylua \
    && rm /tmp/stylua.zip
