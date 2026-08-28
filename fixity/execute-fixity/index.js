const { SFNClient, StartExecutionCommand } = require("@aws-sdk/client-sfn");
const stateMachineArn = process.env.stateMachineArn;

const fullyDecode = (str) => decodeURIComponent(str.replace(/\+/g, " "));

exports.handler = async (event) => {
  var params = {
    stateMachineArn: stateMachineArn,
    input: JSON.stringify({
      Bucket: fullyDecode(event.Records[0].s3.bucket.name),
      Key: fullyDecode(event.Records[0].s3.object.key),
      Algorithm: ["md5", "sha256"]
    }),
  };
  var stepfunctions = new SFNClient();
  const cmd = new StartExecutionCommand(params);
  try {
    const data = await stepfunctions.send(cmd);
    console.log(data);
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "Step function worked",
      }),
    };
  } catch (err) {
    console.log(err);
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: "There was an error",
      }),
    };
  }
};
