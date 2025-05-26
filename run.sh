#!/bin/bash

set -e

docker compose up -d

# 設定したい遅延時間（必要に応じて変更）
DELAY="1ms"

# 対象コンテナ名
CONTAINERS=("main_ecu" "main_vcu")

# 対象インターフェース
ETHS=("eth0" "eth1" "eth2")

VETHS=()

get_veth_name() {
    local cname=$1
    local eth=$2
    local pid=$(docker inspect -f '{{.State.Pid}}' "$cname")
    local iflink=$(sudo nsenter -t "$pid" -n ip link show "$eth" | grep -o 'if[0-9]\+' | grep -o '[0-9]\+')

    # veth をホスト側から探す
    local veth=$(ip -o link | grep '^'$iflink': ' | awk -F': ' '/veth.*@if/ {split($2, a, "@"); print a[1]}')
    echo "$veth"
}

for cname in "${CONTAINERS[@]}"; do
    for eth in "${ETHS[@]}"; do
        echo "📦 Processing $cname:$eth..."
        veth=$(get_veth_name "$cname" "$eth")
        echo "🔍 Found veth interface: $veth"

        if [ -z "$veth" ]; then
            echo "❌ Could not find veth interface for $cname"
            exit 1
        fi

	VETHS+=("$veth")

        echo "🧹 Deleting old qdisc (if any)..."
        sudo tc qdisc del dev "$veth" root 2>/dev/null || true

        echo "⏱️  Applying delay $DELAY to $veth"
        sudo tc qdisc add dev "$veth" root netem delay $DELAY
    done
done

echo "✅ Delay $DELAY applied to both directions (main_ecu ↔ main_vcu)"

# CPU負荷
echo "stress-ng"
docker exec main_ecu stress-ng --cpu 2 --cpu-load 50 &
docker exec sub_ecu stress-ng --cpu 2 --cpu-load 50 &
docker exec main_vcu stress-ng --cpu 2 --cpu-load 50 &
docker exec sub_vcu stress-ng --cpu 2 --cpu-load 50 &

# TODO: leader election のプロセス起動
docker exec main_ecu ping main_vcu & # この行は削除すること
sleep 5 # この行は削除すること

# Main ECU/Main VCU間ネットワークダウン
echo disconnecting
docker network disconnect leader_election_me_mv main_ecu

# TODO: 計測
sleep 5 # この行は削除すること

# tc の設定を削除
echo "Removing qdisc..."

for veth in "${VETHS[@]}"; do
    echo "   🔸 Removing qdisc from $veth"
    sudo tc qdisc del dev "$veth" root 2>/dev/null || true
done

# 終了
echo "Removing containers..."
docker compose rm -sf
