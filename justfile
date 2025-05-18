

list:
    just -l

# destroy generated folder, and regenerate
genesis-reiterate-DANGEROUS:
    rm -rf treasure-hunt-game*
    # .genesis/sbrodola-v2.sh
    time .genesis/sbrodola-v3.2.sh
