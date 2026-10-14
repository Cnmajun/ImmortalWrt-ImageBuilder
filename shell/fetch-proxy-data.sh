#!/bin/bash
# 编译时自动下载最新代理内核 + IP/域名列表，打包进固件。
# 用法：ARCH=amd64 FILES_DIR=files sh shell/fetch-proxy-data.sh
#   ARCH：amd64（x86-64）| arm64（rockchip / sunxi / N1 等）
# 依赖：curl / tar / base64（GitHub Actions ubuntu + imagebuilder 镜像均自带）
# 注意：set -e，任一下载失败会直接中断编译，避免把空文件打进固件。
set -e
ARCH="${ARCH:-amd64}"
FILES_DIR="${FILES_DIR:-files}"

echo "==> [proxy-data] ARCH=$ARCH FILES_DIR=$FILES_DIR"

# ---------- OpenClash ----------
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
  echo "==> OpenClash: 下载 Meta + Smart 内核 + Geo 数据"
  mkdir -p "$FILES_DIR/etc/openclash/core"

  # Meta 内核（默认）：解包后为 /etc/openclash/core/clash_meta，权限 4755（与插件一致）
  curl -fsSL "https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-${ARCH}.tar.gz" \
    | tar -xzOf - clash > "$FILES_DIR/etc/openclash/core/clash_meta"
  chmod 4755 "$FILES_DIR/etc/openclash/core/clash_meta"

  # Smart 内核：插件只认 clash_meta 一个文件，Smart 无法以独立文件名被插件直接使用。
  # 这里把 Smart tar 包原样存进固件，供手动切换时解压覆盖 clash_meta，避免每次联网重下。
  curl -fsSL "https://raw.githubusercontent.com/vernesong/OpenClash/core/master/smart/clash-linux-${ARCH}.tar.gz" \
    -o "$FILES_DIR/etc/openclash/core/clash_smart.tar.gz"

  # Geo 数据（与插件默认源一致：Loyalsoldier/v2ray-rules-dat 等）
  curl -fsSL "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
    -o "$FILES_DIR/etc/openclash/GeoIP.dat"
  curl -fsSL "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
    -o "$FILES_DIR/etc/openclash/GeoSite.dat"
  curl -fsSL "https://github.com/xishang0128/geoip/releases/latest/download/GeoLite2-ASN.mmdb" \
    -o "$FILES_DIR/etc/openclash/ASN.mmdb"
  curl -fsSL "https://raw.githubusercontent.com/alecthw/mmdb_china_ip_list/release/lite/Country.mmdb" \
    -o "$FILES_DIR/etc/openclash/Country.mmdb"
fi

# ---------- Nikki ----------
if echo "$PACKAGES" | grep -q "nikki"; then
  echo "==> Nikki: 下载 GeoX 数据库"
  mkdir -p "$FILES_DIR/etc/nikki/run"
  # 来源：MetaCubeX/meta-rules-dat（Nikki / mihomo 事实标准上游）
  BASE="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest"
  curl -fsSL "$BASE/geoip.dat"         -o "$FILES_DIR/etc/nikki/run/geoip.dat"
  curl -fsSL "$BASE/geosite.dat"       -o "$FILES_DIR/etc/nikki/run/geosite.dat"
  curl -fsSL "$BASE/geoip.metadb"      -o "$FILES_DIR/etc/nikki/run/geoip.metadb"
  curl -fsSL "$BASE/GeoLite2-ASN.mmdb" -o "$FILES_DIR/etc/nikki/run/GeoLite2-ASN.mmdb"
fi

# ---------- Passwall ----------
if echo "$PACKAGES" | grep -q "passwall"; then
  echo "==> Passwall: 下载 IP / 域名列表"
  # 同时写两处：/usr/share/passwall/rules/ 是已确认的 v1 默认路径；
  # 新版本可能迁到 /etc/passwall/rules/，双写覆盖两种情况（文件小，无负担）。
  for D in "$FILES_DIR/usr/share/passwall/rules" "$FILES_DIR/etc/passwall/rules"; do
    mkdir -p "$D"
    # gfwlist：下载的是 Base64 编码的 gfw.txt，解码后写入 gfwlist（无 .txt 后缀）
    curl -fsSL "https://fastly.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/gfw.txt" \
      | base64 -d > "$D/gfwlist"
    # chnroute / chnroute6：IP 列表（无 .txt 后缀）
    curl -fsSL "https://ispip.clang.cn/all_cn.txt"      -o "$D/chnroute"
    curl -fsSL "https://ispip.clang.cn/all_cn_ipv6.txt" -o "$D/chnroute6"
    # chnlist：域名列表，由 dnsmasq-china-list 的 3 个文件合并
    TMP="$(mktemp -d)"
    for f in apple.china.conf accelerated-domains.china.conf google.china.conf; do
      curl -fsSL "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/refs/heads/master/$f" \
        -o "$TMP/$f"
    done
    cat "$TMP"/apple.china.conf "$TMP"/accelerated-domains.china.conf "$TMP"/google.china.conf > "$D/chnlist"
    rm -rf "$TMP"
  done
  # Passwall 的 Geo 二进制文件（UCI v2ray_location_asset 默认路径）
  mkdir -p "$FILES_DIR/usr/share/v2ray"
  curl -fsSL "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
    -o "$FILES_DIR/usr/share/v2ray/geoip.dat"
  curl -fsSL "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
    -o "$FILES_DIR/usr/share/v2ray/geosite.dat"
fi

echo "==> [proxy-data] 全部下载完成"
