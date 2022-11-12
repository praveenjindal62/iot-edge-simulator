VERSION=v2
docker build -f Dockerfile.amd64 -t praveenjindal62/iot-hub-module:$VERSION .
docker push praveenjindal62/iot-hub-module:$VERSION