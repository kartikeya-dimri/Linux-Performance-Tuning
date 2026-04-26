/*
 * prime.c - CPU-bound stressor for performance experiments
 *
 * Usage: ./prime <num_threads>
 *
 * Each thread computes primes up to UPPER_LIMIT independently.
 * Deterministic, CPU-bound, ~20-40s depending on hardware.
 */

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <math.h>
#include <time.h>

#define UPPER_LIMIT 5000000UL   /* tune if runtime too short/long */

typedef struct {
    int    thread_id;
    unsigned long count;        /* primes found by this thread */
} thread_arg_t;

static int is_prime(unsigned long n)
{
    if (n < 2)  return 0;
    if (n == 2) return 1;
    if (n % 2 == 0) return 0;

    unsigned long limit = (unsigned long)sqrt((double)n);
    for (unsigned long i = 3; i <= limit; i += 2)
        if (n % i == 0) return 0;

    return 1;
}

static void *compute_primes(void *arg)
{
    thread_arg_t *targ = (thread_arg_t *)arg;
    unsigned long count = 0;

    for (unsigned long n = 2; n <= UPPER_LIMIT; n++)
        if (is_prime(n)) count++;

    targ->count = count;
    return NULL;
}

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <num_threads>\n", argv[0]);
        return 1;
    }

    int num_threads = atoi(argv[1]);
    if (num_threads < 1 || num_threads > 128) {
        fprintf(stderr, "Error: num_threads must be between 1 and 128\n");
        return 1;
    }

    pthread_t    *threads = malloc(num_threads * sizeof(pthread_t));
    thread_arg_t *args    = malloc(num_threads * sizeof(thread_arg_t));

    if (!threads || !args) {
        perror("malloc");
        return 1;
    }

    struct timespec t_start, t_end;
    clock_gettime(CLOCK_MONOTONIC, &t_start);

    for (int i = 0; i < num_threads; i++) {
        args[i].thread_id = i;
        args[i].count     = 0;
        if (pthread_create(&threads[i], NULL, compute_primes, &args[i]) != 0) {
            perror("pthread_create");
            return 1;
        }
    }

    unsigned long total = 0;
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
        total += args[i].count;
    }

    clock_gettime(CLOCK_MONOTONIC, &t_end);

    double elapsed = (t_end.tv_sec  - t_start.tv_sec) +
                     (t_end.tv_nsec - t_start.tv_nsec) / 1e9;

    fprintf(stderr, "[prime] threads=%d  primes_found=%lu  wall_time=%.4fs\n",
            num_threads, total, elapsed);

    free(threads);
    free(args);
    return 0;
}
