#Mongo dev cluster
Start a simple sharded Mongodb cluster with replica's for development
purposes.

## Requirements
* Docker
* jsawk
* mongo shell

## How to run
```
export DOCKER_IP=127.0.0.1
./start-cluster.sh
```

## What you get
This will start 10 docker images:

* 2 replica sets of 3 servers
* 3 config servers
* 1 mongos routing server