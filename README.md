# FPGA-Based Ring Oscillator TRNG

This project implements a True Random Number Generator (TRNG) using
ring oscillator jitter on an FPGA. Randomness is generated from the
inherent timing variations (jitter) in multiple ring oscillators and
processed to produce high-entropy random bits suitable for security
applications.

## Features

* Multiple ring oscillators for entropy generation
* XOR-based entropy extraction
* Health tests for randomness monitoring
* SHA hashing for randomness conditioning
* FPGA implementation using Verilog

## System Components

* **Ring Oscillators:** Generate entropy using jitter from multiple oscillator loops.
* **XOR Combiner:** Combines outputs from several oscillators to increase randomness.
* **Health Tests:** Monitor entropy source quality to detect failure or bias.
* **SHA Hashing:** Post-processing stage that improves randomness quality.
* **Output Module:** Produces final random bitstream.

## Project Structure

* `ring_oscillator.v` – Ring oscillator design
* `trng_top.v` – Top-level TRNG module
* `health_test.v` – Online health monitoring
* `sha_conditioner.v` – SHA-based randomness conditioner
* `constraints.xdc` – FPGA constraint file

## Applications

* Cryptography
* Secure key generation
* Hardware security modules
* Embedded security systems

## Author

Jafrin Rubayet
Department of Electrical and Electronic Engineering
Bangladesh University of Engineering and Technology (BUET)
