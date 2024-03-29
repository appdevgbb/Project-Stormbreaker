#!/usr/bin/bash
# export FC and CC to the compilers you want to use
export FC=gfortran
export CC=gcc

apt-get update && apt-get install -y \
    automake \
    autoconf \
    libtool \
    gcc \
    gfortran \
    wget \
    make \
    libxml2-dev \
    openssh-server \
    build-essential \
    m4 \
    vim \
    unzip \
    libcurl4-gnutls-dev
# make a directory to hold source code for adcirc netcdf related dependencies
# doesn't matter what you call it
mkdir -p /home/stormbreaker/src

# make a directory to install homemade binaries, libraries, headers, etc.
# doesn't matter what you call it, but you use it below quite a few times
mkdir -p /home/stormbreaker/install

# change the src dir
cd /home/stormbreaker/src

##############################
# get zlib
wget http://zlib.net/zlib-1.3.1.tar.gz

# get hdf5
wget www.hdfgroup.org/ftp/HDF5/current/src/hdf5-1.10.5.tar.gz

# get netcdf
wget https://github.com/Unidata/netcdf-c/archive/refs/tags/v4.9.2.tar.gz
wget https://downloads.unidata.ucar.edu/netcdf-fortran/4.6.1/netcdf-fortran-4.6.1.tar.gz

####################
# install zlib
tar -xzvf zlib-1.3.1.tar.gz
cd zlib-1.3.1
./configure
make test
make install prefix=/home/stormbreaker/install
cd ../

#######################
# install hdf5
tar -xzvf hdf5-1.10.5.tar.gz
cd hdf5-1.10.5
./configure -with-zlib=/home/stormbreaker/install -prefix=/home/stormbreaker/install -enable-fortran  # don't think you have to enable-fortran, but it doesn't hurt
make
make check
make install
cd ../

#########################
# install netcdf c library
tar -xzvf v4.9.2.tar.gz
cd netcdf-c-4.9.2
export CPPFLAGS=-I/home/stormbreaker/install/include
export LDFLAGS=-L/home/stormbreaker/install/lib
./configure -prefix=/home/stormbreaker/install --disable-dap # dap depends on libcurl

make
make check
make install
cd ../

# note: to link fortran codes must use "-L/home/stormbreaker/install/lib -lnetcdff"
export LD_LIBRARY_PATH=/home/stormbreaker/install/lib  # must do this before running  padcirc. E.g. put it in pbs script.

##########################
# installing adcirc etc.
# look here http://www.unc.edu/ims/adcirc/ADCIRCDevGuide.pdf for detailed instructions
# change to the adcirc "work" directory
# edit the cmplrflags.mk file according to the system and compilers 
# in cmplrflags.mk I set as a default:
# NETCDF=enable 
# NETCDF4=enable
# NETCDF4_COMPRESSION=enable
# NETCDFHOME=/home/stormbreaker/install 
# alternatively(additionally) you can set(override) these on the command line
# as described in the ADCIRC development guide. 
wget https://github.com/adcirc/adcirc/releases/download/v55.02/adcirc_v55.02.tar.gz
tar xvzf adcirc_v55.02.tar.gz
cd adcirc_v55.02/work

NETCDF=enable
NETCDF4=enable
NETCDF4_COMPRESSION=enable
NETCDFHOME=/home/stormbreaker/install

make clobber
make adcirc
make padcirc
cd ../thirdparty/swan
make clobber
make config

sed -i -E 's!(../work/odir4)!../\1!g' macros.inc
make punswan 
make clobber 
cd ../../work
make adcswan
make padcswan
make adcprep SWAN=enable
make hstime
make aswip

for i in adcirc adcprep adcswan aswip hstime padcirc padcswan
do 
    cp $i /home/stormbreaker/install/bin/
done 