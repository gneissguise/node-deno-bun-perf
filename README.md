# Node.js vs. Deno vs. Bun: A Performance Benchmark

This project provides a comprehensive performance comparison of Node.js, Deno, and Bun for a realistic, high-traffic, mixed read/write workload.

The benchmark uses a simple Quiz API built with each of the three runtimes. The API is backed by a PostgreSQL database.

## Features

*   **Quiz API:** A simple REST API for a quiz, with endpoints for fetching questions, fetching a specific question, and submitting answers.
*   **Three Runtimes:** The API is implemented in Node.js (with Express), Deno, and Bun, allowing for a direct performance comparison.
*   **Performance Benchmark:** A shell script (`run_benchmark.sh`) is included to automate the benchmark process. The script uses `autocannon` to generate load and measures requests per second, latency, and memory usage.
*   **Realistic Workload:** The benchmark includes a mix of read and write operations to simulate a real-world workload.

## Performance Benchmark

The benchmark is designed to be as fair as possible, with each runtime running the same API and being subjected to the same load.

### Benchmark Setup

*   **Database:** A PostgreSQL database is used to store the quiz data. The database is run in a Docker container.
*   **Load Generation:** The `autocannon` tool is used to generate a high-concurrency load on the API.
*   **Metrics:** The benchmark measures the following metrics:
    *   **Requests per second:** The number of requests the server can handle per second.
    *   **Latency:** The time it takes for the server to respond to a request.
    *   **Memory usage:** The amount of memory the server uses during the benchmark.

### Benchmark Tests

The benchmark consists of three tests:

*   **Heavy Read:** A `GET` request to the `/questions` endpoint to fetch all questions. This test measures the server's ability to handle a large number of read operations.
*   **Random Read:** A `GET` request to the `/questions/:id` endpoint with a random question ID. This test measures the server's ability to handle random read operations.
*   **Random Write:** A `POST` request to the `/answers` endpoint with a random question and option ID. This test measures the server's ability to handle write operations.

## Getting Started

To run the benchmark, you will need to have the following tools installed:

*   [Docker](https://www.docker.com/)
*   [Docker Compose](https://docs.docker.com/compose/)
*   [Node.js](https://nodejs.org/)
*   [Deno](https://deno.land/)
*   [Bun](https://bun.sh/)
*   [autocannon](https://github.com/mcollina/autocannon)
*   [jq](https://stedolan.github.io/jq/)
*   [curl](https://curl.se/)
*   [shuf](https://www.gnu.org/software/coreutils/manual/html_node/shuf-invocation.html)

Once you have all the required tools installed, you can run the benchmark by following these steps:

1.  Clone the repository:

    ```bash
    git clone https://github.com/your-username/node-deno-bun-perf.git
    ```

2.  Navigate to the project directory:

    ```bash
    cd node-deno-bun-perf
    ```

3.  Run the benchmark script:

    ```bash
    ./run_benchmark.sh
    ```

The script will start the database, run the benchmark for each runtime, and print a summary of the results to the console. The raw JSON results will be saved in the `results` directory.

## Benchmark Results

The benchmark results will be displayed in the console after running the `run_benchmark.sh` script. The results will show a comparison of the performance of Node.js, Deno, and Bun for each of the three tests.

Here is an example of the actual benchmark output:

```
================== BENCHMARK SUMMARY ==================

Category: heavy_read
  Fastest -> Slowest (by requests/sec):
    Rank   Server       Req/sec      Latency(ms)  Mem(KB)   
    1      node         1997.47      62.23        215924    
    2      bun          1745.94      13.84        132812    
    3      deno         977.2        126.76       165804    

  Least -> Most memory (by peak RSS KB):
    Rank   Server       Mem(KB)      Req/sec      Latency(ms)
    1      bun          132812       1745.94      13.84     
    2      deno         165804       977.2        126.76    
    3      node         215924       1997.47      62.23     

Category: random_read
  Fastest -> Slowest (by requests/sec):
    Rank   Server       Req/sec      Latency(ms)  Mem(KB)   
    1      bun          5569.47      3.99         126196    
    2      node         4863.07      25.37        221924    
    3      deno         2339.54      52.86        211056    

  Least -> Most memory (by peak RSS KB):
    Rank   Server       Mem(KB)      Req/sec      Latency(ms)
    1      bun          126196       5569.47      3.99      
    2      deno         211056       2339.54      52.86     
    3      node         221924       4863.07      25.37     

Category: random_write
  Fastest -> Slowest (by requests/sec):
    Rank   Server       Req/sec      Latency(ms)  Mem(KB)   
    1      bun          3308.07      7.06         102588    
    2      node         2941.54      41.97        228728    
    3      deno         1776.87      69.82        212520    

  Least -> Most memory (by peak RSS KB):
    Rank   Server       Mem(KB)      Req/sec      Latency(ms)
    1      bun          102588       3308.07      7.06      
    2      deno         212520       1776.87      69.82     
    3      node         228728       2941.54      41.97     
=======================================================
```

## Contributing

Contributions are welcome! If you have any suggestions or improvements, please feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
