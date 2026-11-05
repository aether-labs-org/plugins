package scope

// Batches splits files into groups whose total argument size stays within
// maxBytes: fixedBytes (the command itself) plus len(name)+1 per file. Order is
// kept; a file larger than the budget gets a batch of its own.
func Batches(files []string, fixedBytes, maxBytes int) [][]string {
	var out [][]string
	var cur []string
	size := fixedBytes
	for _, f := range files {
		cost := len(f) + 1
		if len(cur) > 0 && size+cost > maxBytes {
			out = append(out, cur)
			cur, size = nil, fixedBytes
		}
		cur = append(cur, f)
		size += cost
	}
	if len(cur) > 0 {
		out = append(out, cur)
	}
	return out
}
