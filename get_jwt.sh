JWT_RESPONSE=$(curl -X POST localhost:8080/auth/challenge 2>/dev/null --header "Content-Type: application/json" --verbose  --data '{
    "complexity": 3,
    "challenge": "0844051b66184853ace759705c93ac27c9401ad7",
    "nonce":
      "a1b9e4a0c1bb539ce6f99fccbc9a5ceceb3cab646d94fba7aa1c6d48bfd550421a2b2b47141517883a74c4377cb3f5b68730820d99356d0e41eb84d4612a7e49e5c1be999a294118ba55ec4e28fc6947883c9dc1240f2704e90626d53dfeb391e58942f2b6858451dd57a3cd2f71308f1e370901707f78a126c42a009901a092aa8f02ebce034c4a0359a8140f35427058ed7a1e1d6a9001855e09ea83bb343cf2e20d686297d32f0677e6c048973091e814f8d892f31bf43dd0552dab1dd46368dc304c02de094aeaec02c783ddd9b9878a706c7930b22db137443dfccfc02c7a5f2ea266632361f481628a17e6a4f0e5d2ddd50f3ee7fd3e1331adf365dd32"
  }' )

echo $JWT_RESPONSE | python -c 'import  json,sys; result=json.load(sys.stdin); print(result["'jwt'"])'
