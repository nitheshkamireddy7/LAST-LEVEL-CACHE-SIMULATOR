# Last Level Cache Simulation in SystemVerilog

This repository contains a simulation of a **Last Level Cache (LLC)** implemented in SystemVerilog, demonstrating the functionality of MESI protocol states and cache operations. The cache supports read, write, and snoop operations, and simulates their effects on a multi-way associative cache structure.

---

## **Key Operations**

### 1. Cache Read (Operation `0`):
- **Hit**: 
  - If the requested address is in the cache (`cache_hit`), it's a hit.
  - If the MESI state is `INVALID`, it transitions to `EXCLUSIVE`.
- **Miss**: 
  - If not in the cache, it's a miss.
  - The address is inserted into the first available invalid cache line with the `EXCLUSIVE` state.

### 2. Cache Write (Operation `1`):
- **Hit**:
  - If the requested address is in the cache, it's a hit.
  - The MESI state transitions to `MODIFIED`.
- **Miss**:
  - If not in the cache, it's a miss.
  - The address is inserted into the first available invalid cache line with the `MODIFIED` state.

### 3. Snooped Read (Operation `3`):
- **Hit**:
  - If the requested address is in the cache:
    - If the MESI state is `MODIFIED`, it transitions to `SHARED`.
- **Miss**: 
  - No state change or insertion occurs.

### 4. Snooped Write (Operation `5`):
- **Hit**:
  - If the requested address is in the cache:
    - The MESI state transitions to `INVALID`.
- **Miss**: 
  - No state change or insertion occurs.

### 5. Snooped Invalidate (Operation `6`):
- **Hit**:
  - If the requested address is in the cache:
    - The MESI state transitions to `INVALID`.
- **Miss**: 
  - No state change or insertion occurs.

---

## **Simulation Workflow**

### **1. Input Trace File**
The simulation accepts a trace file containing a sequence of operations and 32-bit addresses. Each line follows the format:



#### **Example Trace File**

- `Operation Code`: Specifies the cache operation (e.g., 0 for Read, 1 for Write, etc.).
- `Address`: 32-bit hexadecimal memory address.

---

### **2. Step-by-Step Execution**
The simulation performs the following steps for each operation in the trace file:

#### **Initial State**
- All `NUM_WAYS` (16) cache lines are initialized to `INVALID`.

#### **Example Operations**

1. **Operation 0 (Cache Read `0xABC123`)**:
   - **Parsing Address**:
     - `TAG = 0xABC`, `INDEX = 0x12`, `OFFSET = 0x3`.
   - **Cache Check**: Miss (all lines are initially `INVALID`).
   - **Action**: 
     - Insert the address into the first available invalid line with the `EXCLUSIVE` state.

2. **Operation 1 (Cache Write `0xDEF456`)**:
   - **Parsing Address**:
     - `TAG = 0xDEF`, `INDEX = 0x45`, `OFFSET = 0x6`.
   - **Cache Check**: Miss.
   - **Action**: 
     - Insert the address into the first available invalid line with the `MODIFIED` state.

3. **Operation 3 (Snooped Read `0xABC123`)**:
   - **Parsing Address**:
     - Same `TAG`, `INDEX`, `OFFSET`.
   - **Cache Check**: Hit (line is in `EXCLUSIVE` state).
   - **Action**: 
     - Transition the MESI state to `SHARED`.

4. **Operation 6 (Snooped Invalidate `0xDEF456`)**:
   - **Parsing Address**:
     - Same `TAG`, `INDEX`, `OFFSET`.
   - **Cache Check**: Hit.
   - **Action**: 
     - Invalidate the cache line.

---

## **Simulation Output**

### **1. Final Cache State**
After processing all operations, the simulator prints the final state of each cache line. For example:

### **2. Cache Statistics**
The simulator also outputs statistics such as:

---

## **Usage Instructions**

1. **Set Up and Compile**
   - Ensure you have a SystemVerilog simulator (e.g., ModelSim, VCS).
   - Compile the module:
     ```
     vlog cache_read.sv
     ```

2. **Provide Trace File**
   - Include the trace file with operations, e.g., `trace.txt`.
   - Run the simulation with:
     ```
     vsim -c -do "run -all" -gfile_name=trace.txt cache_read
     ```

3. **Analyze Output**
   - Review the final cache state and statistics in the simulation log.

---

## **Customizing the Cache**

- **Modify Cache Parameters**:
  - Adjust cache properties like `TAG_BITS`, `INDEX_BITS`, `OFFSET_BITS`, and `NUM_WAYS` by changing their values in the module's parameters.

- **Design Complex Workloads**:
  - Use custom trace files to simulate realistic memory access patterns and evaluate cache performance.

---

## **License**
This project is licensed under the MIT License. See the `LICENSE` file for details.


