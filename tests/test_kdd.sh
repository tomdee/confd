#!/bin/sh

# This is needed for use in the keys for our templates, both the sed commands
# below use them as well as the templates confd uses.
export NODENAME="kube-master"

echo "Waiting for API server to come online"
until kubectl version > /dev/null 2>&1; do
  sleep 1
done

# This will create the dummy nodes and the third party resources we can populate
kubectl apply -f /tests/tprs.yaml > /dev/null 2>&1
kubectl apply -f /tests/nodes.yaml > /dev/null 2>&1

echo "Waiting for TPRs to apply"
# There is a delay when creating the TPRs and them being ready for use, so we
# try to apply the data until it finally makes it into the API server
until kubectl apply -f /tests/tpr_data.yaml > /dev/null 2>&1; do
  sleep 1
done

echo "Getting latest confd templates from calicoctl repo"
git clone https://github.com/projectcalico/calicoctl.git /calicoctl > /dev/null 2>&1
ln -s /calicoctl/calico_node/filesystem/etc/calico/ /etc/calico > /dev/null 2>&1

echo "Building initial toml files"
# This is pulled from the calico_node rc.local script, it generates these three
# toml files populated with the $NODENAME var.
sed "s/NODENAME/$NODENAME/" /etc/calico/confd/templates/bird6_aggr.toml.template > /etc/calico/confd/conf.d/bird6_aggr.toml
sed "s/NODENAME/$NODENAME/" /etc/calico/confd/templates/bird_aggr.toml.template > /etc/calico/confd/conf.d/bird_aggr.toml
sed "s/NODENAME/$NODENAME/" /etc/calico/confd/templates/bird_ipam.toml.template > /etc/calico/confd/conf.d/bird_ipam.toml

# Need to pause as running confd immediately after might result in files not being present.
sync

echo "Running confd against KDD"
confd -kubeconfig=/tests/confd_kubeconfig -onetime -backend=k8s -confdir=/etc/calico/confd -log-level=debug >/dev/null 2>&1 || true
confd -kubeconfig=/tests/confd_kubeconfig -onetime -backend=k8s -confdir=/etc/calico/confd -log-level=debug >/dev/null 2>&1 || true

ret_code=0

for f in `ls /tests/compiled_templates`; do
  echo "Comparing $f"
  if  ! diff -q /tests/compiled_templates/$f /etc/calico/confd/config/$f; then
    echo "${f} templates do not match, showing diff of expected vs received"
    diff /tests/compiled_templates/$f /etc/calico/confd/config/$f
    ret_code=1
  fi
done

exit $ret_code
