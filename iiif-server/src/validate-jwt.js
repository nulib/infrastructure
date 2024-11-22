import { S3Client, HeadObjectCommand } from "@aws-sdk/client-s3";
import IIIF from 'iiif-processor';

export async function validateJwtClaims(jwtClaims, params, config) {
  console.log("Validating JWT claims");
  const currentTime = Math.floor(Date.now() / 1000);

  if (jwtClaims.exp <= currentTime) {
    return { valid: false, reason: "Token expired" }
  }

  if (jwtClaims.sub !== params.id) {
    return { valid: false, reason: "ID mismatch" }
  }

  const fields = ['region', 'size', 'rotation', 'quality', 'format'];
  for (const field of fields) {
    if (jwtClaims[field] && !jwtClaims[field].includes(params[field])) {
      return { valid: false, reason: `${field} mismatch` }
    }
  }

  if (jwtClaims['max-width'] || jwtClaims['max-height']) {
    const dimensions = await s3Dimensions(config.tiffBucket, s3Key(params));

    if (dimensions) {
      const Calculator = IIIF.Versions[params.version].Calculator;
      const calculator = new Calculator(dimensions);

      calculator
        .region(params.region)
        .size(params.size)
        .rotation(params.rotation)
        .quality(params.quality)
        .format(params.format);

      const requestedDimensions = calculator.info().fullSize;

      if (requestedDimensions.width > jwtClaims['max-width']) {
        return { valid: false, reason: "Exceeds max-width" }
      }

      if (requestedDimensions.height > jwtClaims['max-height']) {
        return { valid: false, reason: "Exceeds max-height" }
      }
    }
  }

  return { valid: true };
}

async function s3Dimensions(bucket, key) {
  const input = {
    "Bucket": bucket,
    "Key": key
  }
  try {
    const s3 = new S3Client();
    const cmd = new HeadObjectCommand(input);
    const response = await s3.send(cmd);
    const { Metadata } = response;
    if (Metadata.width && Metadata.height) {
      return {
        width: parseInt(Metadata.width, 10),
        height: parseInt(Metadata.height, 10)
      };
    } else {
      console.log("Missing width and height metadata in S3 object");
      return null;
    }
  } catch (err) {
    console.log("Error fetching S3 object metadata");
    console.log(err);
    return null;
  }
}

function s3Key(params) {
  const pairtree = params.id.match(/.{1,2}/g).join("/");

  return params.poster
    ? `posters/${pairtree}-poster.tif`
    : `${pairtree}-pyramid.tif`;
}
