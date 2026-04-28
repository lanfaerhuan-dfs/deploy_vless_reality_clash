{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": __PORT__,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "__UUID__", "flow": "xtls-rprx-vision" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "__SNI__:443",
          "serverNames": [ "__SNI__" ],
          "privateKey": "__PRIVATE_KEY__",
          "shortIds": [ "" ]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
