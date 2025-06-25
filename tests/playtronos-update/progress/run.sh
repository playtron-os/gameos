#! /bin/bash

source ../../../rootfs/usr/bin/playtronos-update

# show the progress output (for test development)
input_file=$1
if [[ -n "$input_file" ]]; then
	cat $input_file | __report_progress
	exit 0
fi

exit_code=0
for TEST_CASE in $(ls *.log | sed 's/.log$//'); do
	if [[ ! -f $TEST_CASE.expected ]] || [[ ! -f $TEST_CASE.log ]]; then
		echo "$TEST_CASE: MISSING FILES"
		exit_code=1
		continue
	fi

	actual=$(cat $TEST_CASE.log | __report_progress)
	expected=$(cat $TEST_CASE.expected)

	if [[ "$actual" == "$expected" ]]; then
		echo "$TEST_CASE: PASSED"
	else
		echo "$TEST_CASE: FAILED"
		exit_code=1
	fi
done

exit $exit_code
