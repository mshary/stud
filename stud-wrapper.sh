#!/bin/bash
# stud wrapper script for systemd
# Parses configuration file and runs stud with appropriate options
# Supports both old uppercase format and new lowercase format

CONFIG_FILE="${STUD_CONFIG:-/etc/stud/stud.conf}"
STUD_BIN="${STUD_BINARY:-/usr/local/bin/stud}"

die() {
    echo "ERROR: $@" >&2
    exit 1
}

log() {
    echo "INFO: $@" >&2
}

# Default values (using stud's actual defaults)
FRONTEND="[*]:8443"
BACKEND="[127.0.0.1]:8000"
PEM_FILE=""
TLS_VERSION="tls"
CIPHERS=""
SSL_ENGINE=""
PREFER_SERVER_CIPHERS=0
CLIENT=0
WORKERS=1
BACKLOG=100
KEEPALIVE=3600
CHROOT=""
USER=""
GROUP=""
QUIET=0
SYSLOG=0
SYSLOG_FACILITY="daemon"
WRITE_IP=0
WRITE_PROXY=0
PROXY_PROXY=0
DAEMON=0

# Parse configuration file if it exists
parse_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log "Configuration file $config_file not found, using defaults"
        return 0
    fi
    
    log "Loading configuration from $config_file"
    
    # Read the config file line by line
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Trim whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Remove quotes from value
        value=$(echo "$value" | sed "s/^['\"]//;s/['\"]$//")
        
        # Convert old uppercase format to lowercase if needed
        case "$key" in
            FRONTEND|FRONTEND_ADDRESS)
                key="frontend"
                ;;
            BACKEND|BACKEND_ADDRESS)
                key="backend"
                ;;
            CERT_FILE|PEM_FILE)
                key="pem-file"
                ;;
            TLS_VERSION)
                key="tls"
                # Map TLS_VERSION values to stud format
                case "$value" in
                    tls11) TLS_VERSION="tls11" ;;
                    tls12) TLS_VERSION="tls12" ;;
                    tls13) TLS_VERSION="tls13" ;;
                    tls-all) TLS_VERSION="tls-all" ;;
                    ssl) TLS_VERSION="ssl" ;;
                    *) TLS_VERSION="tls" ;;
                esac
                continue
                ;;
            CIPHER_SUITE|CIPHERS)
                key="ciphers"
                ;;
            ENGINE|SSL_ENGINE)
                key="ssl-engine"
                ;;
            PREFER_SERVER_CIPHERS)
                key="prefer-server-ciphers"
                ;;
            CLIENT_MODE|CLIENT)
                key="client"
                ;;
            WORKERS)
                key="workers"
                ;;
            BACKLOG)
                key="backlog"
                ;;
            KEEPALIVE)
                key="keepalive"
                ;;
            CHROOT)
                key="chroot"
                ;;
            USER)
                key="user"
                ;;
            GROUP)
                key="group"
                ;;
            QUIET)
                key="quiet"
                ;;
            SYSLOG)
                key="syslog"
                ;;
            SYSLOG_FACILITY)
                key="syslog-facility"
                ;;
            WRITE_IP)
                key="write-ip"
                ;;
            WRITE_PROXY)
                key="write-proxy"
                ;;
            PROXY_PROXY)
                key="proxy-proxy"
                ;;
            DAEMON)
                key="daemon"
                ;;
        esac
        
        # Set the variable based on the key
        case "$key" in
            frontend)
                FRONTEND="$value"
                ;;
            backend)
                BACKEND="$value"
                ;;
            pem-file)
                PEM_FILE="$value"
                ;;
            tls|ssl|tls11|tls12|tls13|tls-all)
                # Handle TLS version as boolean flags
                if [ "$value" = "on" ] || [ "$value" = "yes" ] || [ "$value" = "true" ] || [ "$value" = "1" ]; then
                    TLS_VERSION="$key"
                fi
                ;;
            ciphers)
                CIPHERS="$value"
                ;;
            ssl-engine)
                SSL_ENGINE="$value"
                ;;
            prefer-server-ciphers)
                if [ "$value" = "on" ] || [ "$value" = "yes" ] || [ "$value" = "true" ] || [ "$value" = "1" ]; then
                    PREFER_SERVER_CIPHERS=1
                fi
                ;;
            client)
                if [ "$value" = "on" ] || [ "$value" = "yes" ] || [ "$value" = "true" ] || [ "$value" = "1" ]; then
                    CLIENT=1
                fi
                ;;
            workers)
                WORKERS="$value"
                ;;
            backlog)
                BACKLOG="$value"
                ;;
            keepalive)
                KEEPALIVE="$value"
                ;;
            chroot)
                CHROOT="$value"
                ;;
            user)
                USER="$value"
                ;;
            group)
                GROUP="$value"
                ;;
            quiet)
                if [ "$value" = "on" ] || [ "$value" = "yes" ] || [ "$value" = "true" ] || [ "$value" = "1" ]; then
                    QUIET=1
                fi
                ;;
            syslog)
                if [ "$value" = "on" ] || [ "$value" = "yes" ] || [ "$value" = "true" ] || [ "$value" = "1" ]; then
                    SYSLOG=1
                fi
                ;;
            syslog-facility)
                SYSLOG_FACILITY="$value"
                ;;
            write-ip)
                if [ "$value" = "on" ] || [ "$value" = "yes" ] || [ "$value" = "true" ] || [ "$value" = "1" ]; then
                    WRITE_IP=1
                fi
                ;;
            write-proxy)
                if [ "$value" = "on" ] || [ "$value" = "yes" ] || [ "$value" = "true" ] || [ "$value" = "1" ]; then
                    WRITE_PROXY=1
                fi
                ;;
            proxy-proxy)
                if [ "$value" = "on" ] || [ "$value" = "yes" ] || [ "$value" = "true" ] || [ "$value" = "1" ]; then
                    PROXY_PROXY=1
                fi
                ;;
            daemon)
                if [ "$value" = "on" ] || [ "$value" = "yes" ] || [ "$value" = "true" ] || [ "$value" = "1" ]; then
                    DAEMON=1
                fi
                ;;
            *)
                log "Unknown configuration key: $key"
                ;;
        esac
    done < "$config_file"
}

# Parse the configuration file
parse_config "$CONFIG_FILE"

# Validate required options
if [ -z "$PEM_FILE" ]; then
    die "pem-file must be specified in configuration"
fi

if [ ! -f "$PEM_FILE" ]; then
    die "Certificate file $PEM_FILE does not exist"
fi

# Build command line
CMD="$STUD_BIN"

# Frontend and backend
CMD="$CMD --frontend=\"$FRONTEND\""
CMD="$CMD --backend=\"$BACKEND\""

# TLS version
case "$TLS_VERSION" in
    tls)
        CMD="$CMD --tls"
        ;;
    ssl)
        CMD="$CMD --ssl"
        ;;
    tls11)
        CMD="$CMD --tls11"
        ;;
    tls12)
        CMD="$CMD --tls12"
        ;;
    tls13)
        CMD="$CMD --tls13"
        ;;
    tls-all)
        CMD="$CMD --tls-all"
        ;;
    *)
        CMD="$CMD --tls"
        log "Unknown TLS_VERSION '$TLS_VERSION', using default (tls)"
        ;;
esac

# Cipher suite
if [ -n "$CIPHERS" ]; then
    CMD="$CMD --ciphers=\"$CIPHERS\""
fi

# Engine
if [ -n "$SSL_ENGINE" ]; then
    CMD="$CMD --ssl-engine=\"$SSL_ENGINE\""
fi

# Prefer server ciphers
if [ "$PREFER_SERVER_CIPHERS" = "1" ]; then
    CMD="$CMD --prefer-server-ciphers"
fi

# Client mode
if [ "$CLIENT" = "1" ]; then
    CMD="$CMD --client"
fi

# Workers
if [ "$WORKERS" -gt 1 ]; then
    CMD="$CMD --workers=$WORKERS"
fi

# Backlog
if [ "$BACKLOG" -gt 0 ]; then
    CMD="$CMD --backlog=$BACKLOG"
fi

# Keepalive
if [ "$KEEPALIVE" -gt 0 ]; then
    CMD="$CMD --keepalive=$KEEPALIVE"
fi

# Chroot
if [ -n "$CHROOT" ]; then
    CMD="$CMD --chroot=\"$CHROOT\""
fi

# User
if [ -n "$USER" ]; then
    CMD="$CMD --user=\"$USER\""
fi

# Group
if [ -n "$GROUP" ]; then
    CMD="$CMD --group=\"$GROUP\""
fi

# Quiet
if [ "$QUIET" = "1" ]; then
    CMD="$CMD --quiet"
fi

# Syslog
if [ "$SYSLOG" = "1" ]; then
    CMD="$CMD --syslog"
    CMD="$CMD --syslog-facility=\"$SYSLOG_FACILITY\""
fi

# Write IP
if [ "$WRITE_IP" = "1" ]; then
    CMD="$CMD --write-ip"
fi

# Write proxy
if [ "$WRITE_PROXY" = "1" ]; then
    CMD="$CMD --write-proxy"
fi

# Proxy proxy
if [ "$PROXY_PROXY" = "1" ]; then
    CMD="$CMD --proxy-proxy"
fi

# Daemon mode (for systemd, we don't use --daemon)
if [ "$DAEMON" = "1" ]; then
    CMD="$CMD --daemon"
fi

# Certificate file (must be last)
CMD="$CMD \"$PEM_FILE\""

# Log the command (without sensitive info)
log "Starting stud with configuration from $CONFIG_FILE"
log "Command: $(echo "$CMD" | sed 's/--[^ ]* [^ ]*//g')"

# Execute
eval exec $CMD
