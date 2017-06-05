#!/bin/sh

export NODENAME="kube-master"

echo "Getting latest confd templates from calicoctl"
/usr/bin/git clone https://github.com/projectcalico/calicoctl.git
/bin/ln -s /calicoctl/calico_node/filesystem/etc/calico/ /etc/calico

echo "Building initial toml files"
sed "s/NODENAME/$NODENAME/" /etc/calico/confd/templates/bird6_aggr.toml.template > /etc/calico/confd/conf.d/bird6_aggr.toml
sed "s/NODENAME/$NODENAME/" /etc/calico/confd/templates/bird_aggr.toml.template > /etc/calico/confd/conf.d/bird_aggr.toml
sed "s/NODENAME/$NODENAME/" /etc/calico/confd/templates/bird_ipam.toml.template > /etc/calico/confd/conf.d/bird_ipam.toml

# Need to pause as running
sleep 1

echo "Running confd against KDD"
/bin/confd -kubeconfig=/tests/confd_kubeconfig -onetime -backend=k8s -confdir=/etc/calico/confd -log-level=debug >/dev/null 2>&1 || true
/bin/confd -kubeconfig=/tests/confd_kubeconfig -onetime -backend=k8s -confdir=/etc/calico/confd -log-level=debug >/dev/null 2>&1 || true

ret_code=0

for f in `ls /tests/compiled_templates`; do
  echo "Comparing $f"
  /usr/bin/diff -q /tests/compiled_templates/$f /etc/calico/confd/config/$f
  if [ $? != 0 ]; then
    echo "${f} templates do not match, showing diff of expected vs received"
    /usr/bin/diff /tests/compiled_templates/$f /etc/calico/confd/config/$f
    ret_code=1
  fi
done

exit $ret_code
