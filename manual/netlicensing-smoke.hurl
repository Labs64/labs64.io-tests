POST {{netlicensing_base_url}}/licensee/ITEST-DEMO/validate
Content-Type: application/x-www-form-urlencoded
Accept: application/json

productModuleNumber0=MTEST-DEMO

HTTP 200
[Asserts]
jsonpath "$.valid" == true
