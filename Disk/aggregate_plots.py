import os
import re

import matplotlib.pyplot as plt


RESULTS_PATH = os.path.join(os.path.dirname(__file__), "Results.md")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "aggregated_plots")


def load_results_text(path):
	with open(path, "r", encoding="utf-8") as f:
		return f.read()


def split_workload_blocks(text):
	blocks = {}
	patterns = {
		"Random": r"## 1\. Random Workload[\s\S]*?(?=\n---|\Z)",
		"Sequential": r"## 2\. Sequential Workload[\s\S]*?(?=\n---|\Z)",
		"Mixed": r"## 3\. Mixed Workload[\s\S]*?(?=\n---|\Z)",
	}
	for name, pattern in patterns.items():
		match = re.search(pattern, text)
		if not match:
			raise ValueError(f"Missing workload section: {name}")
		blocks[name] = match.group(0)
	return blocks


def parse_table_row(block, label):
	pattern = rf"\|\s*{re.escape(label)}\s*\|\s*([^|]+)\|\s*([^|]+)\|"
	match = re.search(pattern, block)
	if not match:
		raise ValueError(f"Missing row '{label}'")
	return match.group(1).strip(), match.group(2).strip()


def parse_number(value):
	num = re.search(r"[-+]?[0-9]*\.?[0-9]+", value.replace(",", ""))
	if not num:
		raise ValueError(f"No numeric value found in '{value}'")
	return float(num.group(0))


def parse_bandwidth_mib(value):
	value_clean = value.replace(",", "")
	num = parse_number(value_clean)
	if "GiB/s" in value_clean:
		return num * 1024.0
	if "MiB/s" in value_clean:
		return num
	if "KiB/s" in value_clean:
		return num / 1024.0
	return num


def parse_latency_ms(value):
	return parse_number(value)


def parse_psi(block):
	baseline, tuned = parse_table_row(block, "`psi_some_avg10`")
	return parse_number(baseline), parse_number(tuned)


def parse_random_or_seq(block):
	iops = tuple(map(parse_number, parse_table_row(block, "IOPS")))
	bw = tuple(parse_bandwidth_mib(v) for v in parse_table_row(block, "Bandwidth"))
	avg_lat = tuple(parse_latency_ms(v) for v in parse_table_row(block, "Avg clat"))
	p999 = tuple(parse_latency_ms(v) for v in parse_table_row(block, "P99.9 latency"))
	psi = parse_psi(block)
	return {
		"IOPS": iops,
		"Bandwidth": bw,
		"Avg. latency": avg_lat,
		"P99.9 latency": p999,
		"PSI I/O pressure": psi,
	}


def parse_mixed(block):
	read_iops = tuple(map(parse_number, parse_table_row(block, "Read IOPS")))
	write_iops = tuple(map(parse_number, parse_table_row(block, "Write IOPS")))
	iops = (read_iops[0] + write_iops[0], read_iops[1] + write_iops[1])

	read_bw = tuple(parse_bandwidth_mib(v) for v in parse_table_row(block, "Read BW"))
	write_bw = tuple(parse_bandwidth_mib(v) for v in parse_table_row(block, "Write BW"))
	bw = (read_bw[0] + write_bw[0], read_bw[1] + write_bw[1])

	read_lat = tuple(parse_latency_ms(v) for v in parse_table_row(block, "Read avg clat"))
	write_lat = tuple(parse_latency_ms(v) for v in parse_table_row(block, "Write avg clat"))
	avg_lat = ((read_lat[0] + write_lat[0]) / 2.0, (read_lat[1] + write_lat[1]) / 2.0)

	read_p999 = tuple(parse_latency_ms(v) for v in parse_table_row(block, "Read P99.9"))
	write_p999 = tuple(parse_latency_ms(v) for v in parse_table_row(block, "Write P99.9"))
	p999 = ((read_p999[0] + write_p999[0]) / 2.0, (read_p999[1] + write_p999[1]) / 2.0)

	psi = parse_psi(block)

	return {
		"IOPS": iops,
		"Bandwidth": bw,
		"Avg. latency": avg_lat,
		"P99.9 latency": p999,
		"PSI I/O pressure": psi,
	}


def build_dataset(text):
	blocks = split_workload_blocks(text)
	data = {
		"Random": parse_random_or_seq(blocks["Random"]),
		"Sequential": parse_random_or_seq(blocks["Sequential"]),
		"Mixed": parse_mixed(blocks["Mixed"]),
	}
	return data


def plot_metric(metric, unit, data, output_dir):
	workloads = ["Random", "Sequential", "Mixed"]
	before_vals = [data[w][metric][0] for w in workloads]
	after_vals = [data[w][metric][1] for w in workloads]

	x = list(range(len(workloads)))
	width = 0.35

	plt.figure(figsize=(8, 5))
	before_bars = plt.bar([i - width / 2 for i in x], before_vals, width=width, color="red", label="Before")
	after_bars = plt.bar([i + width / 2 for i in x], after_vals, width=width, color="green", label="After")
	plt.xticks(x, workloads)
	plt.ylabel(unit)
	plt.title(metric)
	plt.legend()
	plt.gca().bar_label(before_bars, fmt="%.2f", padding=3)
	plt.gca().bar_label(after_bars, fmt="%.2f", padding=3)
	plt.tight_layout()

	filename = metric.lower().replace(" ", "_").replace(".", "").replace("/", "_") + ".png"
	plt.savefig(os.path.join(output_dir, filename))
	plt.close()


def main():
	text = load_results_text(RESULTS_PATH)
	data = build_dataset(text)

	os.makedirs(OUTPUT_DIR, exist_ok=True)

	metric_units = {
		"IOPS": "IOPS",
		"Bandwidth": "MiB/s",
		"Avg. latency": "ms",
		"P99.9 latency": "ms",
		"PSI I/O pressure": "psi_some_avg10",
	}

	for metric, unit in metric_units.items():
		plot_metric(metric, unit, data, OUTPUT_DIR)

	print(f"[+] Aggregated plots saved in {OUTPUT_DIR}")


if __name__ == "__main__":
	main()
