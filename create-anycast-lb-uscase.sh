#!/bin/bash
openstack stack create -t heat/anycast-lb-lab.yaml -e heat/anycast-lb-lab-env.yaml anycast-lb-lab
