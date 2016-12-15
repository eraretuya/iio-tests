#!/bin/bash

# al3320a's 7-bit I2C slave address
i2c_addr=0x1c
# name of driver being tested
name=$(echo $0 | cut -f2 -d/ | cut -f1 -d.)

# unload i2c-stub if already active
modprobe -r i2c-stub 2>/dev/null
modprobe i2c-stub chip_addr=${i2c_addr}
if [ $? -ne 0 ]
then
    echo "Failed to load the i2c-stub. Must be root."
    exit 1
fi

i2c_adapter=$(i2cdetect -l | grep "SMBus stub driver" | cut -f1 | cut -f2 -d-)
if [ "${i2c_adapter}" = "" ]
then
    echo "I2C adapter not found."
    exit 1
fi

i2cset -f -y ${i2c_adapter} ${i2c_addr} 0x00 0x01 b
i2cset -f -y ${i2c_adapter} ${i2c_addr} 0x07 0x04 b
# set the data in the data register (low) to 0x64 / 100 (decimal)
i2cset -f -y ${i2c_adapter} ${i2c_addr} 0x22 0x64 w
i2cset -f -y ${i2c_adapter} ${i2c_addr} 0x23 0x25 w

echo ${name} ${i2c_addr} > /sys/class/i2c-adapter/i2c-${i2c_adapter}/new_device

# Add delay after instantiating the device
sleep 1

iio_device=$(grep -l ${name} /sys/bus/iio/devices/*/name | cut -f6 -d/ | cut -f2 -d:)
if [ "${iio_device}" = "" ]
then
    echo "Error: ${name} not found."
    exit 1
fi

# Check if the device name matches the expected name
device_name=$(cat /sys/bus/iio/devices/iio:${iio_device}/name)
if [ "${device_name}" != "${name}" ]
then
    echo "Device name does not match."
    exit 1
fi

# Check if the in_illuminance_* attributes exist
attr_prefix="in_illuminance_"
attr_name=("raw" "scale" "scale_available")
attr_dir="/sys/bus/iio/devices/iio:${iio_device}/${attr_prefix}"
for attr in "${attr_name[@]}"
do
    if [ ! -e "${attr_dir}${attr}" ]
    then
	echo "Attribute ${attr_dir}${attr} does not exist."
	exit 1
    else
	echo "Attribute ${attr_dir}${attr} found."
    fi
done

# Cross-check values of in_illuminance_scale_available
expected_vals=("0.512" "0.128" "0.032" "0.01")
scale_avail=$(cat ${attr_dir}scale_available)
if [ "${scale_avail}" != "${expected_vals[*]}" ]
then
    echo "Scale values does not match expected values."
    exit 1
else
    echo "Scale values match the expected values."
fi

# Check value of in_illuminance_scale if corresponds to one of the scales
# found in in_illuminance_scale_available
scale=$(cat ${attr_dir}scale)
# Extra 0's due to intended formatting
expected_scales=("0.512000" "0.128000" "0.032000" "0.010000")
for val in "${expected_scales[@]}"
do
    if [ "${scale}" = "${val}" ]
    then
	echo "Scale read from ${attr_dir}scale fall within expected values."
    fi
done

# Test writing of values to in_illuminance_scale
# Read the value afterwards to confirm if the write is successful
vals_to_write=("0.512000" "0.9" "0.128" "5" "0.032" "0.010" "0.01")
for v in "${vals_to_write[@]}"
do
    echo "Writing $v to scale..."
    echo $v > "${attr_dir}scale"
    echo $(cat ${attr_dir}scale)
done

# Check if the data matches with what was written to the register
# Written value 0x64, equivalent to 100 in decimal
data_raw=$(cat /sys/bus/iio/devices/iio:${iio_device}/${attr_prefix}raw)
if [ "${data_raw}" = "100" ]
then
    echo "Raw data matches with expected value."
else
    echo "Raw data does not match with the expected value."
    exit 1
fi
