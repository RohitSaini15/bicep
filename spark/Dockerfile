# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

FROM --platform=linux/amd64 public.ecr.aws/amazonlinux/amazonlinux:2023-minimal AS base

# FROM --platform=linux/amd64 public.ecr.aws/amazonlinux/amazonlinux:2023 AS base

RUN cat /etc/os-release

COPY cert[s]/ /etc/pki/ca-trust/source/anchors/
RUN update-ca-trust extract

# RUN dnf install -y python3.12

# RUN alias python3='python3.12'

# RUN alias

# RUN python3 --version
RUN dnf install -y gcc python3 python3-devel
RUN dnf install -y python3.12 python3.12-devel

RUN python3.12 --version
RUN python3 --version

# RUN dnf install -y gcc 

# RUN export REQUESTS_CA_BUNDLE=/etc/pki/ca-trust/source/anchors/kainos-chain3.crt

ENV VIRTUAL_ENV=/opt/venv
RUN python3.12 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

COPY . .

RUN python3.12 -m pip install --upgrade pip

RUN python3.12 -m pip --version

# RUN python3 -m pip config set global.cert /etc/pki/ca-trust/source/anchors/kainos-chain.pem
# RUN pip config set global.cert /etc/pki/ca-trust/source/anchors/kainos-chain.pem

RUN python3.12 -m pip config set global.use-feature truststore

# RUN export PIP_CERT=/etc/pki/ca-trust/source/anchors/kainos-chain.pem

# RUN python3 -m pip install pip-system-certs

RUN python3.12 -m pip install venv-pack==0.2.0 && \
    python3.12 -m pip install .

RUN mkdir /venv-package && venv-pack -f -o /venv-package/pyspark-env.tar.gz && chmod ugo+r /venv-package/pyspark-env.tar.gz