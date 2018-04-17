#!/bin/bash
openstack stack create -t heat/bgpaas-lab.yaml -e heat/bgpaas-lab-env.yaml bgpaas-lab