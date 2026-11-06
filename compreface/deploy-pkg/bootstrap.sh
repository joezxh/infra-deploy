#!/bin/bash
# CompreFace 远端服务引导：登录 OWNER -> 创建应用 -> 创建 VERIFY/DETECTION 服务 -> 输出两个 key
set -e
BASE=http://127.0.0.1:8051/admin
EMAIL=sp3-ops@mediation.local
PASSWORD=Sp3-Face-2026-Verify

TOKEN=$(curl -s -X POST $BASE/oauth/token -u CommonClientId:password \
  -d "username=$EMAIL&password=$PASSWORD&grant_type=password" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
echo "token_len=${#TOKEN}"

APP=$(curl -s -X POST $BASE/app -H "Cookie: CFSESSION=$TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"sp3-face-verify"}')
echo "APP=$APP"
GUID=$(echo "$APP" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

VKEY=$(curl -s -X POST $BASE/app/$GUID/model -H "Cookie: CFSESSION=$TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"face-verify-1to1","type":"VERIFY"}' | sed -n 's/.*"apiKey":"\([^"]*\)".*/\1/p')
DKEY=$(curl -s -X POST $BASE/app/$GUID/model -H "Cookie: CFSESSION=$TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"face-detect","type":"DETECTION"}' | sed -n 's/.*"apiKey":"\([^"]*\)".*/\1/p')

echo "VKEY=$VKEY"
echo "DKEY=$DKEY"
