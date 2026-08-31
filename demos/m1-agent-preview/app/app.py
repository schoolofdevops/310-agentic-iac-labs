import os

import redis
from flask import Flask, jsonify

app = Flask(__name__)
r = redis.Redis.from_url(os.environ.get("REDIS_URL", "redis://redis:6379/0"))


@app.get("/health")
def health():
    r.ping()
    return jsonify(status="ok")


@app.get("/stats")
def stats():
    count = r.incr("request_count")
    return jsonify(requests=count)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
