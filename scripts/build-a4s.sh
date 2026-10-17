#!/usr/bin/env bash
# 把 ACL4SSR 的规则源转成 mihomo mrs
#
# 用法: bash scripts/build-a4s.sh [mihomo 可执行文件路径]     # 默认 ./mihomo
#
# 产物:
#   dist/a4s/<Name>_domain.mrs   域名集（DOMAIN-SUFFIX -> +.x，DOMAIN -> x）
#   dist/a4s/<Name>_ip.mrs       IP 集（IP-CIDR / IP-CIDR6）
#   dist/a4s/keywords.tsv        domain 型 mrs 表达不了的 DOMAIN-KEYWORD 清单（集名 + 关键字）
#                                → 这些关键字要在 mihomo 侧写成显式 DOMAIN-KEYWORD 规则
#
# 规则来源只有 ACL4SSR 自身（https://github.com/ACL4SSR/ACL4SSR），不引入第三方规则源。
set -euo pipefail

MIHOMO=${1:-./mihomo}
BASE="https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash"
OUT="dist/a4s"
TMP=".tmp/a4s"
KW="$OUT/keywords.tsv"
mkdir -p "$OUT" "$TMP"
: > "$KW"

# name:相对路径   （domain 集：取 DOMAIN/DOMAIN-SUFFIX，DOMAIN-KEYWORD 记录到 keywords.tsv）
DOMAIN_SETS="
LocalAreaNetwork:LocalAreaNetwork.list
ChinaDomain:ChinaDomain.list
AI:Ruleset/AI.list
YouTube:Ruleset/YouTube.list
Google:Ruleset/Google.list
Github:Ruleset/Github.list
OneDrive:Ruleset/OneDrive.list
Microsoft:Ruleset/Microsoft.list
Apple:Ruleset/Apple.list
Telegram:Ruleset/Telegram.list
TikTok:Ruleset/TikTok.list
Netflix:Ruleset/Netflix.list
Binance:Ruleset/Binance.list
Crypto:Ruleset/Crypto.list
SteamCN:Ruleset/SteamCN.list
Steam:Ruleset/Steam.list
NaSDDNS:Ruleset/NaSDDNS.list
"

# name:相对路径   （ip 集：取 IP-CIDR / IP-CIDR6）
IP_SETS="
ChinaIp:ChinaIp.list
ChinaIpV6:ChinaIpV6.list
ChinaCompanyIp:ChinaCompanyIp.list
LocalAreaNetwork:LocalAreaNetwork.list
Apple:Ruleset/Apple.list
Google:Ruleset/Google.list
Telegram:Ruleset/Telegram.list
NetflixIP:Ruleset/NetflixIP.list
NaSDDNS:Ruleset/NaSDDNS.list
"

# 额外输出纯 CIDR 文本（一行一个），给 OpenClash 的 chnr_custom_url / chnr6_custom_url 用
TXT_SETS="ChinaIp ChinaIpV6"

fetch() { curl -fsSL "$BASE/$1" -o "$2"; }

echo "==== domain 集 ===="
for item in $DOMAIN_SETS; do
  name=${item%%:*}; path=${item#*:}
  src="$TMP/${name}.list"
  fetch "$path" "$src"
  norm="$TMP/${name}.domain.txt"
  awk -F, -v nm="$name" -v kwfile="$KW" '
    { sub(/\r$/, "") }
    $1 == "DOMAIN-SUFFIX"  { print "+." $2; next }
    $1 == "DOMAIN"         { print $2;   next }
    $1 == "DOMAIN-KEYWORD" { sub(/^[[:space:]]+/, "", $2); if ($2 != "") print nm "\t" $2 >> kwfile; next }
  ' "$src" | sed 's/[[:space:]]//g' | grep -v '^$' > "$norm" || true
  n=$(wc -l < "$norm")
  if [ "$n" -gt 0 ]; then
    "$MIHOMO" convert-ruleset domain text "$norm" "$OUT/${name}_domain.mrs"
    echo "$name _domain: $n 条 -> $(stat -c %s "$OUT/${name}_domain.mrs") bytes"
  else
    echo "$name _domain: 0 条，跳过"; rm -f "$OUT/${name}_domain.mrs"
  fi
done

echo "==== ip 集 ===="
for item in $IP_SETS; do
  name=${item%%:*}; path=${item#*:}
  src="$TMP/${name}.list"
  [ -f "$src" ] || fetch "$path" "$src"
  norm="$TMP/${name}.ip.txt"
  tr -d '\r' < "$src" | grep -E '^IP-CIDR6?,' \
    | sed -E 's/^IP-CIDR6?,//; s/,no-resolve$//; s/[[:space:]]//g' > "$norm" || true
  n=$(wc -l < "$norm")
  if [ "$n" -gt 0 ]; then
    "$MIHOMO" convert-ruleset ipcidr text "$norm" "$OUT/${name}_ip.mrs"
    echo "$name _ip: $n 条 -> $(stat -c %s "$OUT/${name}_ip.mrs") bytes"
  else
    echo "$name _ip: 0 条，跳过"; rm -f "$OUT/${name}_ip.mrs"
  fi
  for t in $TXT_SETS; do
    if [ "$t" = "$name" ] && [ "$n" -gt 0 ]; then
      cp "$norm" "$OUT/${name}_ip.txt"
      echo "$name _ip.txt: $n 行（给 OpenClash chnr 用）"
    fi
  done
done

sort -u -o "$KW" "$KW"
echo "==== 需要写成 DOMAIN-KEYWORD 规则的关键字（domain mrs 无法表达）===="
cat "$KW"

rm -rf "$TMP"
echo "==== 产物 ===="
ls -l "$OUT"

# 为什么不用 ACL4SSR 自带的 mrs（Clash/mrs/<Name>_domain.mrs）：
#   实测能被 mihomo 加载、/providers/rules 的 ruleCount 与源条数一致，但匹配不到任何域名
#   （同一测试里 www.google.com 只命中 MetaCubeX geosite google，没命中 ACL4SSR 的 Google_domain）。
#   原因是其 workflow 直接用 convert-ruleset 吃带 DOMAIN-SUFFIX, 前缀的 clash ruleset 语法，
#   产出的条目不是裸域名。IP 类 mrs（*_ip.mrs）实测匹配正常，但为统一维护这里一并自己转。
