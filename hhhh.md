docker build -t defi-mooc-lab2 .
docker run -e ALCHE_API="https://eth-mainnet.g.alchemy.com/v2/1Ok4K6XD2b9DVCJkznLGmo0lmgfgAKz9" -it defi-mooc-lab2 npm test
