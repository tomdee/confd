#!/bin/sh
# This is needed for use in the keys of our templates, and the sed commands
# below use them to create the toml files.
export NODENAME="kube-master"

echo "Populating etcd with test data"
# The empty data needs to be eval'd with the entire command else we end up with ""
# instead of empty values for these keys.
while read cmd; do
  eval $cmd > /dev/null 2>&1
done < /tests/etcd_empty_data

# We set a bunch of data used to populate the templates.
while read data; do
  etcdctl set $data > /dev/null 2>&1
done < /tests/etcd_data

# Some directories that are required to exist for the templates.
while read dir; do
  etcdctl mkdir $dir > /dev/null 2>&1
done < /tests/etcd_dirs

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

# Use ETCD_ENDPOINTS in preferences to ETCD_AUTHORITY
		ETCD_NODE=http://127.0.0.1:2379

		# confd needs a "-node" arguments for each etcd endpoint.
		ETCD_ENDPOINTS_CONFD=`echo "-node=$ETCD_NODE" | sed -e 's/,/ -node=/g'`

		confd -confdir=/etc/calico/confd -onetime ${ETCD_ENDPOINTS_CONFD} \
			  -client-key=${ETCD_KEY_FILE} -client-cert=${ETCD_CERT_FILE} \
			  -client-ca-keys=${ETCD_CA_CERT_FILE} -keep-stage-file >/felix-startup-1.log 2>&1 || true
		confd -confdir=/etc/calico/confd -onetime ${ETCD_ENDPOINTS_CONFD} \
			  -client-key=${ETCD_KEY_FILE} -client-cert=${ETCD_CERT_FILE} \
			  -client-ca-keys=${ETCD_CA_CERT_FILE} -keep-stage-file >/felix-startup-2.log 2>&1 || true

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
