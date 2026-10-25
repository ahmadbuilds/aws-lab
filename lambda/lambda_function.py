"""Public CV HTTP handler using private S3 and its execution role."""
import base64
import json
import os
import time

import boto3

_S3 = boto3.client("s3")


def lambda_handler(event, context):
    started = time.perf_counter()
    request_context = (event or {}).get("requestContext") or {}
    http_context = request_context.get("http") or {}
    path = (event or {}).get("rawPath") or http_context.get("path") or "/"
    fn = os.environ.get("AWS_LAMBDA_FUNCTION_NAME", "unknown")
    status = 500
    try:
        files = {
            "/": ("index.html", "text/html; charset=utf-8"),
            "/index.html": ("index.html", "text/html; charset=utf-8"),
            "/style.css": ("style.css", "text/css; charset=utf-8"),
            "/cv.pdf": ("cv.pdf", "application/pdf"),
        }
        if path not in files:
            status = 404
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "text/html; charset=utf-8"},
                "body": "<html><body><h1>404 Not Found</h1></body></html>",
                "isBase64Encoded": False,
            }
        key, mime_type = files[path]
        bucket = os.environ["BUCKET"]
        prefix = os.environ["PREFIX"].strip("/")
        obj = _S3.get_object(Bucket=bucket, Key=f"{prefix}/{key}")
        raw = obj["Body"].read()
        headers = {"Content-Type": mime_type}
        binary = (key == "cv.pdf")
        if binary:
            body = base64.b64encode(raw).decode("ascii")
        else:
            body = raw.decode("utf-8")
            if key == "index.html":
                body = body.replace("{{HOSTED_ON}}", f"Lambda {fn}")
                headers["Cache-Control"] = "max-age=60"
        status = 200
        return {"statusCode": 200, "headers": headers,
                "body": body, "isBase64Encoded": binary}
    except Exception as exc:
        # Errors are logged without leaking bucket names or credentials to visitors.
        status = 500
        print(json.dumps({"error_type": type(exc).__name__}))
        return {"statusCode": 500,
                "headers": {"Content-Type": "text/html; charset=utf-8"},
                "body": "<html><body><h1>Temporary server error</h1></body></html>",
                "isBase64Encoded": False}
    finally:
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        print(json.dumps({"fn": fn, "path": path, "status": status, "ms": elapsed_ms},
                         separators=(",", ":")))
