#!/usr/bin/env bash

: "${NUM_WORKERS:=1}"
SAVED_IMG=/tmp/okn-ubuntu.tar
IMG_NAME=okn-ubuntu

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

pushd $THIS_DIR

OKN_YML=$THIS_DIR/../../../../build/yamls/okn.yml

if [ ! -f ssh-config ]; then
    echo "File ssh-config does not exist in current directory"
    echo "Did you run ./provision.sh?"
    exit 1
fi

docker inspect $IMG_NAME > /dev/null
if [ $? -ne 0 ]; then
    echo "Docker image $IMG_NAME was not found"
    exit 1
fi

echo "Saving $IMG_NAME image to $SAVED_IMG"
docker save -o $SAVED_IMG $IMG_NAME

echo "Copying $IMG_NAME image to every node..."
# Copy image to master
scp -F ssh-config $SAVED_IMG k8s-node-master:/tmp/okn-ubuntu.tar &
# Loop over all worker nodes and copy image to each one
for ((i=1; i<=$NUM_WORKERS; i++)); do
    name="k8s-node-worker-$i"
    scp -F ssh-config $SAVED_IMG $name:/tmp/okn-ubuntu.tar &
done
# Wait for all child processes to complete
wait
echo "Done!"

echo "Loading $IMG_NAME image in every node..."
ssh -F ssh-config k8s-node-master docker load -i /tmp/okn-ubuntu.tar &
# Loop over all worker nodes and copy image to each one
for ((i=1; i<=$NUM_WORKERS; i++)); do
    name="k8s-node-worker-$i"
    ssh -F ssh-config $name docker load -i /tmp/okn-ubuntu.tar &
done
# Wait for all child processes to complete
wait
echo "Done!"

echo "Copying OKN deployment YAML to every node..."
scp -F ssh-config $OKN_YML k8s-node-master:~/ &
# Loop over all worker nodes and copy image to each one
for ((i=1; i<=$NUM_WORKERS; i++)); do
    name="k8s-node-worker-$i"
    scp -F ssh-config $OKN_YML $name:~/ &
done
# Wait for all child processes to complete
wait
echo "Done!"

# To ensure that the most recent version of OKN (that we just pushed) will be
# used.
echo "Restarting OKN DaemonSet"
ssh -F ssh-config k8s-node-master kubectl -n kube-system delete daemonset.apps/okn-agent
ssh -F ssh-config k8s-node-master kubectl apply -f okn.yml
echo "Done!"