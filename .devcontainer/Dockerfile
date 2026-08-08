FROM mcr.microsoft.com/devcontainers/base:alpine-3.20

RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 luacheck build-base curl unzip github-cli \
    && ln -sf /usr/bin/lua5.1 /usr/local/bin/lua \
    && luarocks-5.1 install busted LUA_INCDIR=/usr/include \
    && curl -fsSL "https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-linux-x86_64-musl.zip" \
        -o /tmp/stylua.zip \
    && unzip /tmp/stylua.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/stylua \
    && rm /tmp/stylua.zip

# .NET SDK, for ad hoc scripting with file-based apps (`dotnet run app.cs`).
# Nothing in this repo is built with it — it is a scratch-scripting tool, which
# is why it gets its own layer and does not invalidate the Lua one above.
#
# Alpine is musl, so there is no apk package: the official install script drops
# a self-contained SDK in, and the apk line is the runtime's documented musl
# dependency list (icu-libs keeps globalization working rather than forcing
# DOTNET_SYSTEM_GLOBALIZATION_INVARIANT).
ENV DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    PATH=/usr/share/dotnet:$PATH

RUN apk add --no-cache ca-certificates libgcc libssl3 libstdc++ zlib icu-libs \
    && curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel 10.0 --install-dir "$DOTNET_ROOT" --no-path \
    && rm /tmp/dotnet-install.sh \
    && ln -sf "$DOTNET_ROOT/dotnet" /usr/local/bin/dotnet \
    && dotnet --version
