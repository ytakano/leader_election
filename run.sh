docker compose up -d

# CPU負荷
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

# 終了
docker compose rm -sf
