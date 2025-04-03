module llc;

  parameter int TAG_BITS = 12;
  parameter int INDEX_BITS = 14; // 2^14 sets
  parameter int OFFSET_BITS = 6;
  parameter int NUM_WAYS = 16;
  parameter int NUM_SETS = 2**INDEX_BITS;

  typedef enum logic[1:0] {
    INVALID = 2'b00,
    EXCLUSIVE = 2'b01,
    MODIFIED = 2'b10,
    SHARED = 2'b11
  } mesi_state_t;

  typedef struct packed {
    logic[TAG_BITS-1:0] tag;
    mesi_state_t mesi_state;
  } cache_line_t;

  cache_line_t cache[NUM_SETS][NUM_WAYS];
  logic [NUM_SETS][NUM_WAYS-2:0] tree; // Tree for replacement policy per set
  logic [NUM_SETS-1:0] reserved; // Reserve information for each set (whether it is reserved for a particular index)

  string file_name;
  int file, r;
  bit [3:0] cache_op;
  bit [31:0] address;
  int way, set_index;
  logic[TAG_BITS-1:0] tag;
  logic[INDEX_BITS-1:0] index;
  logic[OFFSET_BITS-1:0] offset;
  logic hit;
  int total_accesses, total_hits, total_misses;
  int cache_reads, cache_writes; // Count cache reads and writes separately
  string mode; // To store the simulation mode: silent or normal

  // Parse the address into tag, index, and offset
  function void parse_address(input bit[31:0] addr, 
                              output logic[TAG_BITS-1:0] tag, 
                              output logic[INDEX_BITS-1:0] index, 
                              output logic[OFFSET_BITS-1:0] offset);
    tag = addr[31:20];            // Extract TAG_BITS from the address
    index = addr[19:6];           // Extract INDEX_BITS from the address
    offset = addr[5:0];           // Extract OFFSET_BITS from the address
  endfunction

  // Check for a cache hit in a specific set
  function logic check_cache_hit(input logic[TAG_BITS-1:0] tag, 
                                 input int set_index,
                                 output int way_hit);
    integer i;
    begin
      hit = 0;
      way_hit = -1;

      for (i = 0; i < NUM_WAYS; i++) begin
        if (cache[set_index][i].mesi_state != INVALID && cache[set_index][i].tag == tag) begin
          hit = 1;
          way_hit = i;
          break;
        end
      end
      return hit;
    end
  endfunction

  // Get the replacement way in a specific set (following the tree-based replacement policy)
  function int get_replacement_way(input int set_index);
    automatic int node;
    int way;
    node = 0;
    for (int level = 0; level < $clog2(NUM_WAYS); level++) begin
      if (tree[set_index][node] == 0)
        node = 2 * node + 1; // Left child
      else
        node = 2 * node + 2; // Right child
    end
    way = node - (NUM_WAYS - 1); // Map leaf node to way
    return way;
  endfunction

  // Update the tree after an access in a specific set
  function void update_tree(input int set_index, input int way);
    automatic int node;
    automatic int parent;
    node = way + (NUM_WAYS - 1);
    while (node > 0) begin
      parent = (node - 1) >> 1; // Calculate parent node
      tree[set_index][parent] = (node % 2); // Update parent based on left (0) or right (1) child
      node = parent; // Move to parent
    end
  endfunction

  // Print the state of the LRU bits (tree array) for a set
  task print_lru_tree(input int set_index);
    integer i;
    $write("Set %0d LRU Bits: ", set_index);
    for (i = 0; i < NUM_WAYS - 1; i++) begin
      $write("%0d ", tree[set_index][i]);
    end
    $write("\n");
  endtask
  task handle_read(input logic[TAG_BITS-1:0] tag, input int set_index);
    integer way_hit, way;
    logic hit;
    begin
      hit = check_cache_hit(tag, set_index, way_hit);
      total_accesses++; // Increment total accesses
      cache_reads++; // Increment reads
      if (hit) begin
        total_hits++;
        if (mode == "normal")
          $display("Read hit: Set %0d, Way %0d, Tag %h", set_index, way_hit, tag);
        update_tree(set_index, way_hit);
      end else begin
        total_misses++;
        way = get_replacement_way(set_index);
        cache[set_index][way].tag = tag;
        cache[set_index][way].mesi_state = EXCLUSIVE;
        if (mode == "normal")
          $display("Read miss: Set %0d, Replacing Way %0d, New Tag %h", set_index, way, tag);
        update_tree(set_index, way);
      end
    end
  endtask

  task handle_write(input logic[TAG_BITS-1:0] tag, input int set_index);
    integer way_hit, replacement_way;
    begin
      total_accesses++; // Increment total accesses
      cache_writes++; // Increment writes
      if (check_cache_hit(tag, set_index, way_hit)) begin
        total_hits++;
        cache[set_index][way_hit].mesi_state = MODIFIED;
        if (mode == "normal")
          $display("Write hit: Set %0d, Way %0d, Tag %h", set_index, way_hit, tag);
        update_tree(set_index, way_hit);
      end else begin
        total_misses++;
        replacement_way = get_replacement_way(set_index);
        cache[set_index][replacement_way].tag = tag;
        cache[set_index][replacement_way].mesi_state = MODIFIED;
        if (mode == "normal")
          $display("Write miss: Set %0d, Replacing Way %0d, New Tag %h", set_index, replacement_way, tag);
        update_tree(set_index, replacement_way);
      end
    end
  endtask

  task handle_snoop_read(input logic[TAG_BITS-1:0] tag, input int set_index, input string mode);
  integer way_hit;
  logic hit;
  begin
    hit = check_cache_hit(tag, set_index, way_hit);
    if (hit) begin
      if (mode == "normal") 
        $display("SNOOP READ: Transitioning to SHARED");
      cache[set_index][way_hit].mesi_state = SHARED;
    end
  end
endtask
task handle_snoop_write(input logic[TAG_BITS-1:0] tag, input int set_index, input string mode);
  integer way_hit;
  logic hit;

  begin
    hit = check_cache_hit(tag, set_index, way_hit);
    if (hit) begin
      if (mode == "normal")
        $display("SNOOP WRITE: Invalidating line");
      cache[set_index][way_hit].mesi_state = INVALID;
    end
  end
endtask
task handle_snoop_read_modify(input logic[TAG_BITS-1:0] tag, input int set_index, input string mode);
  integer way_hit;
  logic hit;

  begin
    hit = check_cache_hit(tag, set_index, way_hit);
    if (hit) begin
      if (mode == "normal")
        $display("SNOOP READ INTEND TO MODIFY: Invalidating line");
      cache[set_index][way_hit].mesi_state = INVALID;
    end
  end
endtask
task handle_snoop_bus_upgrade(input logic[TAG_BITS-1:0] tag, input int set_index, input string mode);
  integer way_hit;
  logic hit;

  begin
    hit = check_cache_hit(tag, set_index, way_hit);
    if (hit) begin
      if (mode == "normal")
        $display("SNOOP BUS UPGRADE: Invalidating line");
      cache[set_index][way_hit].mesi_state = INVALID;
    end
  end
endtask

  // Print all valid cache lines
  task print_valid_cache_lines();
  automatic bit found_valid_line; // Declare the variable as automatic
  integer set, way;
  
  found_valid_line = 0; // Initialize the variable separately
  
  $display("----------------------------------------------------");
  $display("Valid Cache Lines:");
  
  for (set = 0; set < NUM_SETS; set++) begin
    for (way = 0; way < NUM_WAYS; way++) begin
      if (cache[set][way].mesi_state != INVALID) begin
        found_valid_line = 1; // Set flag when a valid line is found
        $display("Set: %0d, Way: %0d, Tag: %h, State: %s", 
                 set, way, cache[set][way].tag, cache[set][way].mesi_state.name());
      end
    end
  end
  
  if (!found_valid_line) begin
    $display("No valid cache lines found.");
  end
endtask


  // Reset the entire cache
  task reset_cache();
    integer set, way;
    $display("Resetting Cache...");
    for (set = 0; set < NUM_SETS; set++) begin
      tree[set] = '{default: 0};
      reserved[set] = 0;
      for (way = 0; way < NUM_WAYS; way++) begin
        cache[set][way].mesi_state = INVALID;
        cache[set][way].tag = 0;
      end
    end
  endtask

  initial begin
    total_accesses = 0;
    total_hits = 0;
    total_misses = 0;
    cache_reads = 0;
    cache_writes = 0;

    if (!$value$plusargs("mode=%s", mode)) begin
      $display("Error: Please specify the simulation mode using +mode=<silent|normal>");
      $finish;
    end

    if (!$value$plusargs("file_name=%s", file_name)) begin
      $display("Error: Please provide the input file name using +file_name=<filename>");
      $finish;
    end

    file = $fopen(file_name, "r");
    if (file == 0) begin
      $display("Error opening file: %s", file_name);
      $finish;
    end

    while (!$feof(file)) begin
      int way_hit;

      r = $fscanf(file, "%d %h\n", cache_op, address);
      if (r != 2) continue;

      parse_address(address, tag, index, offset);
      set_index = index; // Directly use index as the set_index

      if (mode == "normal") begin
        $display("----------------------------------------------------");
        $display("Access %0d: Address = %h", total_accesses + 1, address);
      end

      case (cache_op)
        0, 2: handle_read(tag, set_index);
        1: handle_write(tag, set_index);
        3: handle_snoop_read(tag, set_index, mode);
        4: handle_snoop_write(tag, set_index, mode);
        5: handle_snoop_read_modify(tag, set_index, mode);
        6: handle_snoop_bus_upgrade(tag, set_index, mode);
        8: reset_cache();
        9: begin
       if (mode == "silent") begin
         $display("----------------------------------------------------");
         print_valid_cache_lines();
       end
     end
      endcase
    end

    $fclose(file);
    $display("Simulation complete.");
    $display("----------------------------------------------------");
    $display("Summary:");
    $display("Total Accesses = %0d", total_accesses);
    $display("Total Reads = %0d", cache_reads);
    $display("Total Writes = %0d", cache_writes);
    $display("Total Hits = %0d", total_hits);
    $display("Total Misses = %0d", total_misses);
    if (total_accesses > 0) begin
      $display("Hit Ratio = %f", ((real'(total_hits) / total_accesses)*100));
      $display("Miss Ratio = %f", ((real'(total_misses) / total_accesses)*100));
    end else begin
      $display("No cache accesses to calculate hit or miss ratios.");
    end
  end

endmodule
