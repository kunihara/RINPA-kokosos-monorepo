FROM node:20-alpine
WORKDIR /app

# Wrangler + deps
RUN npm i -g wrangler@^3.78.0

# App deps
COPY package.json package-lock.json* .npmrc* ./
RUN npm ci || npm i

COPY . .

# dev 起動（コンテナで wrangler dev を0.0.0.0:8787で公開）
CMD ["sh","-lc","wrangler dev --ip 0.0.0.0 --port 8787"]
