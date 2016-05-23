#!/bin/bash

#VARIABLES
#------------------------------------------------------------------------------#
MONGO_IMAGE="mongo:3.2"
DOCKER_IP=${DOCKER_IP:-default}

#FUNCTIONS
#------------------------------------------------------------------------------#
function log {
  echo "========================================="
  echo " $1"
  echo "========================================="
}

function replicaset_rename {
  mongo --host $1 --port $2 --eval "cfg=rs.conf(); cfg.members[0].host='$3'; rs.reconfig(cfg);"
}

#replicaset_status returns the status of a replicaset
# <PUB_HOST> <PUB_PORT>
function replicaset_status {
  mongo --host $1 --port $2 --eval "rs.status();"
}

#replicaset_add ads a node to a set
# <PUB_HOST> <PUB_PORT> <NODE_IP+PORT>
function replicaset_add {
  mongo --host $1 --port $2 --eval "rs.add('$3');"
}

#setup_replicaset <PUB_HOST> <PUB_PORT> <NODE1> <NODE2> <NODE3>
function replicaset_setup {
  mongo --host $1 --port $2 --eval "rs.initiate();"
  replicaset_add $1 $2 $4
  replicaset_add $1 $2 $5
  replicaset_rename $1 $2 $3
  replicaset_status $1 $2
}

#router_add_shard adds a shard to the router
# <PUB_HOST> <PUB_PORT> <REPLICA-SET> <NODE>
function router_add_shard {
  mongo --host $1 --port $2 --eval "sh.addShard('$3/$4');"
}

#router_shard_status
# <PUB_HOST> <PUB_PORT>
function router_shard_status {
  mongo --host $1 --port $2 --eval "sh.status();"
}

#SCRIPT
#------------------------------------------------------------------------------#

#start replicaset 1
log "Creating replicaset 1..."
docker run \
  -P --name rs1_srv1 \
  -d ${MONGO_IMAGE} \
  --replSet rs1 \
  --noprealloc --smallfiles
docker run \
  -P --name rs1_srv2 \
  -d ${MONGO_IMAGE} \
  --replSet rs1 \
  --noprealloc --smallfiles
docker run \
  -P --name rs1_srv3 \
  -d ${MONGO_IMAGE} \
  --replSet rs1 \
  --noprealloc --smallfiles

# #start replicaset 2
log "Creating replicaset 2..."
docker run \
  -P --name rs2_srv1 \
  -d ${MONGO_IMAGE} \
  --replSet rs2 \
  --noprealloc --smallfiles
docker run \
  -P --name rs2_srv2 \
  -d ${MONGO_IMAGE} \
  --replSet rs2 \
  --noprealloc --smallfiles
docker run \
  -P --name rs2_srv3 \
  -d ${MONGO_IMAGE} \
  --replSet rs2 \
  --noprealloc --smallfiles

log "Sleeping for 5 sec..."
sleep 5

#get ip addresses etc.
log "Gathering information from docker..."
RS1_SRV1_IP_PRIV=$(docker inspect rs1_srv1 | jsawk -a 'return this[0].NetworkSettings.IPAddress')
RS1_SRV2_IP_PRIV=$(docker inspect rs1_srv2 | jsawk -a 'return this[0].NetworkSettings.IPAddress')
RS1_SRV3_IP_PRIV=$(docker inspect rs1_srv3 | jsawk -a 'return this[0].NetworkSettings.IPAddress')
RS2_SRV1_IP_PRIV=$(docker inspect rs2_srv1 | jsawk -a 'return this[0].NetworkSettings.IPAddress')
RS2_SRV2_IP_PRIV=$(docker inspect rs2_srv2 | jsawk -a 'return this[0].NetworkSettings.IPAddress')
RS2_SRV3_IP_PRIV=$(docker inspect rs2_srv3 | jsawk -a 'return this[0].NetworkSettings.IPAddress')

RS1_SRV1_IP_PUB=${DOCKER_IP}
#RS1_SRV1_IP_PUB=$(docker inspect rs1_srv1 | jsawk -a 'return this[0].NetworkSettings.Ports["27017/tcp"][0]["HostIp"]')
RS1_SRV1_PORT_PUB=$(docker inspect rs1_srv1 | jsawk -a 'return this[0].NetworkSettings.Ports["27017/tcp"][0]["HostPort"]')

RS2_SRV1_IP_PUB=${DOCKER_IP}
#RS2_SRV1_IP_PUB=$(docker inspect rs2_srv1 | jsawk -a 'return this[0].NetworkSettings.Ports["27017/tcp"][0]["HostIp"]')
RS2_SRV1_PORT_PUB=$(docker inspect rs2_srv1 | jsawk -a 'return this[0].NetworkSettings.Ports["27017/tcp"][0]["HostPort"]')

#configure replica sets
log "Configure replicaset 1..."
replicaset_setup ${RS1_SRV1_IP_PUB} ${RS1_SRV1_PORT_PUB} "${RS1_SRV1_IP_PRIV}:27017" "${RS1_SRV2_IP_PRIV}:27017" "${RS1_SRV3_IP_PRIV}:27017"

log "Configure replicaset 2..."
replicaset_setup ${RS2_SRV1_IP_PUB} ${RS2_SRV1_PORT_PUB} "${RS2_SRV1_IP_PRIV}:27017" "${RS2_SRV2_IP_PRIV}:27017" "${RS2_SRV3_IP_PRIV}:27017"


#create config servers
log "Creating config servers..."
docker run \
  -P --name cfg1 \
  -d ${MONGO_IMAGE} \
  --noprealloc --smallfiles \
  --configsvr \
  --dbpath /data/db \
  --port 27017
docker run \
  -P --name cfg2 \
  -d ${MONGO_IMAGE} \
  --noprealloc --smallfiles \
  --configsvr \
  --dbpath /data/db \
  --port 27017
docker run \
  -P --name cfg3 \
  -d ${MONGO_IMAGE} \
  --noprealloc --smallfiles \
  --configsvr \
  --dbpath /data/db \
  --port 27017


#get ipaddresses
log "Gathering information from docker..."
CFG1_IP_PRIV=$(docker inspect cfg1 | jsawk -a 'return this[0].NetworkSettings.IPAddress')
CFG2_IP_PRIV=$(docker inspect cfg2 | jsawk -a 'return this[0].NetworkSettings.IPAddress')
CFG3_IP_PRIV=$(docker inspect cfg3 | jsawk -a 'return this[0].NetworkSettings.IPAddress')

log "Sleeping for 5 sec..."
sleep 5

#create router mongos
log "Create Mongos router..."
docker run \
  -P --name mongos1 \
  -d ${MONGO_IMAGE} \
  mongos \
  --port 27017 \
  --configdb "${CFG1_IP_PRIV}:27017,${CFG2_IP_PRIV}:27017,${CFG3_IP_PRIV}:27017"

#get ipaddresses
log "Gathering information from docker..."
ROUTER_IP_PUB=${DOCKER_IP}
#ROUTER_IP_PUB=$(docker inspect mongos1 | jsawk -a 'return this[0].NetworkSettings.Ports["27017/tcp"][0]["HostIp"]')
ROUTER_PORT_PUB=$(docker inspect mongos1 | jsawk -a 'return this[0].NetworkSettings.Ports["27017/tcp"][0]["HostPort"]')

log "Sleeping for 5 sec..."
sleep 5

#configure shards
log "Configure shards..."
router_add_shard ${ROUTER_IP_PUB} ${ROUTER_PORT_PUB} "rs1" "${RS1_SRV1_IP_PRIV}:27017"
router_add_shard ${ROUTER_IP_PUB} ${ROUTER_PORT_PUB} "rs2" "${RS2_SRV1_IP_PRIV}:27017"
router_shard_status ${ROUTER_IP_PUB} ${ROUTER_PORT_PUB}

#done
echo "----------------------------------------------------------------------------"
echo "Done!"
echo "Connect to mongo via mongos1(router) on: ${ROUTER_IP_PUB}:${ROUTER_PORT_PUB}"
echo "----------------------------------------------------------------------------"



