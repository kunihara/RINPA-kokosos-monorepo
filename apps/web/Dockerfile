FROM node:20-alpine
WORKDIR /app

COPY package.json package-lock.json* .npmrc* ./
RUN npm ci || npm i

COPY . .

# Next.js dev server を 0.0.0.0:3000 で公開
CMD ["sh","-lc","next dev -H 0.0.0.0 -p 3000"]
