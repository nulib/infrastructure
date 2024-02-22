const { defaultProvider } = require("@aws-sdk/credential-provider-node");
const { SignatureV4 } = require("@smithy/signature-v4");
const { NodeHttpHandler } = require("@smithy/node-http-handler");
const { Sha256 } = require("@aws-crypto/sha256-browser");
const { AWS_REGION } = process.env;

async function awsFetch(request) {
  const signer = new SignatureV4({
    credentials: defaultProvider(),
    region: AWS_REGION,
    service: "es",
    sha256: Sha256
  });

  const signedRequest = await signer.sign(request);

  const client = new NodeHttpHandler();
  const { response } = await client.handle(signedRequest);

  return await new Promise((resolve, _reject) => {
    let returnValue = {
      statusCode: response.statusCode
    };
    let responseBody = "";

    response.body.on("data", function (chunk) {
      responseBody += chunk;
    });
    response.body.on("end", function (_chunk) {
      resolve({ ...returnValue, body: responseBody });
    });
  });
}

module.exports = { awsFetch };
