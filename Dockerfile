# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

FROM mcr.microsoft.com/azureml/o16n-base/python-assets@sha256:c27baec2ee25a627a71c5147031d47b47d54090201f6acd839606e84492c93a3 AS inferencing-assets

# Tag: cuda:10.0-cudnn7-devel-ubuntu18.04
# Env: CUDA_VERSION=10.0.130
# Env: CUDA_PKG_VERSION=10-0=10.0.130-1
# Env: NCCL_VERSION=2.4.8
# Env: CUDNN_VERSION=7.6.3.30
# Env: NVIDIA_VISIBLE_DEVICES=all
# Env: NVIDIA_DRIVER_CAPABILITIES=compute,utility
# Env: NVIDIA_REQUIRE_CUDA=cuda>=10.0 brand=tesla,driver>=384,driver<385 brand=tesla,driver>=410,driver<411
# Label: com.nvidia.cuda.version=10.0.130
# Label: com.nvidia.cudnn.version=7.6.3.30
# Label: com.nvidia.volumes.needed=nvidia_driver
# Ubuntu 18.04
FROM nvidia/cuda:10.0-cudnn7-devel-ubuntu18.04

USER root:root

ENV com.nvidia.cuda.version $CUDA_VERSION
ENV com.nvidia.volumes.needed nvidia_driver
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV DEBIAN_FRONTEND noninteractive
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64
ENV NCCL_DEBUG=INFO
ENV HOROVOD_GPU_ALLREDUCE=NCCL

# Install Common Dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # SSH and RDMA
    libmlx4-1 \
    libmlx5-1 \
    librdmacm1 \
    libibverbs1 \
    libmthca1 \
    libdapl2 \
    dapl2-utils \
    openssh-client \
    openssh-server \
    iproute2 && \
    # Others
    apt-get install -y \
    build-essential \
    bzip2=1.0.6-8.1ubuntu0.2 \
    libbz2-1.0=1.0.6-8.1ubuntu0.2 \
    systemd \
    git=1:2.17.1-1ubuntu0.7 \
    wget \
    cpio \
    libsm6 \
    libxext6 \
    libxrender-dev \
    fuse && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# Inference
# Copy logging utilities, nginx and rsyslog configuration files, IOT server binary, etc.
COPY --from=inferencing-assets /artifacts /var/
RUN /var/requirements/install_system_requirements.sh && \
    cp /var/configuration/rsyslog.conf /etc/rsyslog.conf && \
    cp /var/configuration/nginx.conf /etc/nginx/sites-available/app && \
    ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app && \
    rm -f /etc/nginx/sites-enabled/default
ENV SVDIR=/var/runit
ENV WORKER_TIMEOUT=300
EXPOSE 5001 8883 8888

# Intel MPI installation
ENV INTEL_MPI_VERSION 2018.3.222
ENV PATH $PATH:/opt/intel/compilers_and_libraries/linux/mpi/bin64
RUN cd /tmp && \
    wget -q "http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/13063/l_mpi_${INTEL_MPI_VERSION}.tgz" && \
    tar zxvf l_mpi_${INTEL_MPI_VERSION}.tgz && \
    sed -i -e 's/^ACCEPT_EULA=decline/ACCEPT_EULA=accept/g' /tmp/l_mpi_${INTEL_MPI_VERSION}/silent.cfg && \
    cd /tmp/l_mpi_${INTEL_MPI_VERSION} && \
    ./install.sh -s silent.cfg --arch=intel64 && \
    cd / && \
    rm -rf /tmp/l_mpi_${INTEL_MPI_VERSION}* && \
    rm -rf /opt/intel/compilers_and_libraries_${INTEL_MPI_VERSION}/linux/mpi/intel64/lib/debug* && \
    echo "source /opt/intel/compilers_and_libraries_${INTEL_MPI_VERSION}/linux/mpi/intel64/bin/mpivars.sh" >> ~/.bashrc

# python, pip, setuptools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.6 python3-dev python3-pip python3-setuptools python3-numpy python3-matplotlib python3-tk && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# default to Python3
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.6 100
RUN update-alternatives --set python /usr/bin/python3.6

# default to Pip3
RUN update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 100
RUN update-alternatives --set pip /usr/bin/pip3

# HOROVOD: set before running pip
ENV HOROVOD_GPU_BROADCAST=NCCL
ENV HOROVOD_GPU_OPERATIONS=NCCL

# project related python libraries: install from requirements.txt
WORKDIR /opt/pip
COPY ./requirements.txt .
RUN pip install --no-cache-dir --upgrade pip
RUN pip install --no-cache-dir --use-feature=2020-resolver -r requirements.txt