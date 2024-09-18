const authorize = require("./authorize");
const middy = require("@middy/core");
const secretsManager = require("@middy/secrets-manager");

function getEventHeader(request, name) {
  if (
    request.headers &&
    request.headers[name] &&
    request.headers[name].length > 0
  ) {
    return request.headers[name][0].value;
  } else {
    return undefined;
  }
}

function viewerRequestOptions(request) {
  const origin = getEventHeader(request, "origin") || "*";
  return {
    status: "200",
    statusDescription: "OK",
    headers: {
      "access-control-allow-headers": [
        { key: "Access-Control-Allow-Headers", value: "authorization, cookie" }
      ],
      "access-control-allow-credentials": [
        { key: "Access-Control-Allow-Credentials", value: "true" }
      ],
      "access-control-allow-methods": [
        { key: "Access-Control-Allow-Methods", value: "GET, OPTIONS" }
      ],
      "access-control-allow-origin": [
        { key: "Access-Control-Allow-Origin", value: origin }
      ]
    },
    body: "OK"
  };
}

function parsePath(path) {
  const segments = path.split(/\//).reverse();

  if (segments.length < 8) {
    return {
      poster: segments[2] == "posters",
      id: segments[1],
      filename: segments[0]
    };
  } else {
    return {
      poster: segments[5] == "posters",
      id: segments[4],
      region: segments[3],
      size: segments[2],
      rotation: segments[1],
      filename: segments[0]
    };
  }
}

async function viewerRequestIiif(request, { config }) {
  const path = decodeURI(request.uri.replace(/%2f/gi, ""));
  const params = parsePath(path);
  const referer = getEventHeader(request, "referer");
  const cookie = getEventHeader(request, "cookie");
  const authed = await authorize(
    params,
    referer,
    cookie,
    request.clientIp,
    config
  );
  console.log("Authorized:", authed);

  // Return a 403 response if not authorized to view the requested item
  if (!authed) {
    return {
      status: "403",
      statusDescription: "Forbidden",
      body: "Forbidden"
    };
  }

  // Set the x-preflight-location request header to the location of the requested item
  const pairtree = params.id.match(/.{1,2}/g).join("/");
  const s3Location = params.poster
    ? `s3://${config.tiffBucket}/posters/${pairtree}-poster.tif`
    : `s3://${config.tiffBucket}/${pairtree}-pyramid.tif`;
  request.headers["x-preflight-location"] = [
    { key: "X-Preflight-Location", value: s3Location }
  ];
  return request;
}

async function processViewerRequest(event, context) {
  console.log("Initiating viewer-request trigger");
  const { request } = event.Records[0].cf;
  let result;

  if (request.method === "OPTIONS") {
    // Intercept OPTIONS request and return proper response
    result = viewerRequestOptions(request);
  } else {
    result = await viewerRequestIiif(request, context);
  }

  return result;
}

// async function logSecret() {
//   const {
//     SecretsManagerClient,
//     GetSecretValueCommand
//   } = require("@aws-sdk/client-secrets-manager");
//   const client = new SecretsManagerClient();
//   const result = await client.send(
//     new GetSecretValueCommand({
//       SecretId: process.env.AWS_LAMBDA_FUNCTION_NAME
//     })
//   );
//   console.log("raw", result.SecretString);
//   console.log("parsed", JSON.parse(result.SecretString));
// }

async function processRequest(event, context) {
  const { eventType } = event.Records[0].cf.config;
  let result;

  console.log("Event Type:", eventType);
  if (eventType === "viewer-request") {
    result = await processViewerRequest(event, context);
  } else {
    result = event.Records[0].cf.request;
  }

  return result;
}

function functionNameAndRegion() {
  let nameVar = process.env.AWS_LAMBDA_FUNCTION_NAME;
  const match = /^(?<functionRegion>[a-z]{2}-[a-z]+-\d+)\.(?<functionName>.+)$/.exec(nameVar);
  if (match) {
    return { ...match.groups }
  } else {
    return {
      functionName: nameVar,
      functionRegion: process.env.AWS_REGION
    }
  }
}

const { functionName, functionRegion } = functionNameAndRegion();
console.log("Initializing", functionName, 'in', functionRegion);

module.exports = { 
  handler:
    middy(processRequest)
    .use(
      secretsManager({
        fetchData: { config: functionName },
        awsClientOptions: { region: functionRegion },
        setToContext: true
      })
    )
};
