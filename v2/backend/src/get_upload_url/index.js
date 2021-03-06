const path = require('path');
const AWS = require('aws-sdk');
const uuid = require('uuid/v4');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Credentials': true,
};

const S3_BUCKET_NAME = process.env.MIPMAPPER_S3_BUCKET || 'mipmapper';
const S3_FOLDER_PREFIX = 'images';
const ALLOWED_IMAGE_TYPES = ['jpg', 'png'];
const MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024;

function getValidationErrors(event) {
  const errors = [];
  if (ALLOWED_IMAGE_TYPES.indexOf(event.imageType) < 0) {
    errors.push('imageType must be png or jpg');
  }

  const fileSizeBytes = event.fileSizeBytes;
  if (!fileSizeBytes) {
    errors.push('fileSizeBytes must be specified');
  } else {
    const fileSizeBytesValue = parseInt(fileSizeBytes, 10);
    if (isNaN(fileSizeBytesValue) || fileSizeBytesValue < 0) {
      errors.push('fileSizeBytes must be a positive integer');
    } else if (fileSizeBytesValue > MAX_FILE_SIZE_BYTES) {
      errors.push('fileSizeBytes cannot exceed 5MB');
    }
  }

  return errors;
}

module.exports = (event, context, done) => {
  const body = JSON.parse(event.body);
  const errors = getValidationErrors(body);
  if (errors.length > 0) {
    done(
      null,
      {
        headers: Object.assign({}, CORS_HEADERS),
        statusCode: 400,
        body: JSON.stringify({ errors }),
      });
    return;
  }

  const id = uuid();
  const filename = `${path.join(S3_FOLDER_PREFIX, 'orig', id)}.${body.imageType}`;
  const params = {
    Bucket: S3_BUCKET_NAME,
    Key: filename,
  };

  console.log('params building done');
  const s3 = new AWS.S3();
  s3.getSignedUrl('putObject', params, (err, url) => {
    console.log(err);
    done(err, {
      headers: Object.assign({}, CORS_HEADERS),
      statusCode: 200,
      body: JSON.stringify({ id, url }),
    });
  });
};
