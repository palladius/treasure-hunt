
VERSION := '0.1.0'

# This is a Justfile for the treasure-hunt-game project.

# It is a simple game where the player has to find a treasure in a grid.
# The game is played in a terminal, and the player can move up, down, left, or right.
# The player can also pick up items and use them to solve puzzles.
# The game is written in Python and uses the Pygame library for graphics and sound.
# The game is designed to be played by one or more players, and can be played in a single session or over multiple sessions.
# The game is designed to be easy to learn and play, but difficult to master.
# The game is designed to be fun and engaging, and to provide a challenge for players of all skill levels.
# The game is designed to be played in a terminal, and the player can move up, down, left, or right.
# The player can also pick up items and use them to solve puzzles.


list:
    just -l

# destroy generated folder, and regenerate
genesis-reiterate-DANGEROUS:
    rm -rf treasure-hunt-game*
    # .genesis/sbrodola-v2.sh
    time .genesis/sbrodola-v3.3.sh
