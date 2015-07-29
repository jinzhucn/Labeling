#ifndef LABELING_ALGS_CL_
#define LABELING_ALGS_CL_

typedef uchar TPixel;
typedef uint  TLabel;

typedef enum TCoherence
{
	COH_4,
	COH_8,
	COH_DEFAULT
} TCoherence;

///////////////////////////////////////////////////////////////////////////////
// TOCLBinLabeling kernels
///////////////////////////////////////////////////////////////////////////////

__kernel void BinLabelingKernel(
	__global TPixel	*pixels, // Image pixels
	__global TLabel	*labels	 // Image labels
	)
{
	uint id = get_global_id(0);
	labels[id] = pixels[id] > 0 ? 1 : 0;
}

///////////////////////////////////////////////////////////////////////////////
// TOCLLabelDistribution kernels
///////////////////////////////////////////////////////////////////////////////

__kernel void DistrInitKernel(
	__global TPixel	*pixels,	// Intermediate buffers
	__global TLabel	*labels		// Image labels
	)
{
	const size_t pos = get_global_id(0);
	labels[pos] = pixels[pos] ? pos : 0;
}

///////////////////////////////////////////////////////////////////////////////

TPixel GetPixel(__global TPixel *pix, size_t pos, uint maxSize) {
	return pos && pos < maxSize ? pix[pos] : 0;
}

///////////////////////////////////////////////////////////////////////////////

TLabel GetLabel(__global TLabel *labels, size_t pos, uint maxSize) {
	return pos && pos < maxSize ? labels[pos] : 0;
}

///////////////////////////////////////////////////////////////////////////////

TLabel MinLabel(TLabel lb1, TLabel lb2)
{
	if (lb1 && lb2)
		return min(lb1, lb2);

	TLabel lb = max(lb1, lb2);

	return lb ? lb : UINT_MAX;
}

///////////////////////////////////////////////////////////////////////////////

TLabel MinNWSELabel(__global TLabel *lb, size_t lbPos, uint width, uint maxPos, TCoherence coh)
{
	if (coh == COH_8)
		return MinLabel(GetLabel(lb, lbPos - 1, maxPos),
		MinLabel(GetLabel(lb, lbPos - width, maxPos),
		MinLabel(GetLabel(lb, lbPos + width, maxPos),
		MinLabel(GetLabel(lb, lbPos - 1 - width, maxPos),
		MinLabel(GetLabel(lb, lbPos + 1 + width, maxPos),
		MinLabel(GetLabel(lb, lbPos - 1 + width, maxPos),
		MinLabel(GetLabel(lb, lbPos + 1 - width, maxPos),
		GetLabel(lb, lbPos + 1, maxPos))))))));
	else
		return MinLabel(GetLabel(lb, lbPos - 1, maxPos),
		MinLabel(GetLabel(lb, lbPos - width, maxPos),
		MinLabel(GetLabel(lb, lbPos + width, maxPos),
		GetLabel(lb, lbPos + 1, maxPos))));
}

///////////////////////////////////////////////////////////////////////////////

__kernel void DistrScanKernel(
	__global TLabel	*labels,	// Image labels
	uint	width,		// Image width
	uint	height,		// Image height
	TCoherence coh,	// CC coherence
	__global char	*noChanges	// Shows if no pixels were changed
	)
{
	const size_t pos = get_global_id(0);

	const size_t size = width * height;
	TLabel label = labels[pos];

	if (label)
	{
		TLabel minLabel = MinNWSELabel(labels, pos, width, size, coh);

		if (minLabel < label)
		{
			TLabel tmpLabel = labels[label];
			labels[label] = min(tmpLabel, minLabel);
			*noChanges = 0;
		}
	}
}

///////////////////////////////////////////////////////////////////////////////

__kernel void DistrAnalizeKernel(__global TLabel *labels)
{
	const size_t pos = get_global_id(0);

	TLabel label = labels[pos];

	if (label){
		TLabel curLabel = labels[label];
		while (curLabel != label)
		{
			label = labels[curLabel];
			curLabel = labels[label];
		}

		labels[pos] = label;
	}
}

///////////////////////////////////////////////////////////////////////////////
// TOCLLabelEquivX2 kernels
///////////////////////////////////////////////////////////////////////////////

inline bool TestBit(__global const TPixel *pix, int px, int py, int xshift, int yshift, int w, int h)
{
	return pix[px + xshift + (py + yshift) * w];
}

///////////////////////////////////////////////////////////////////////////////

inline ushort CheckNeibPixABC(bool C1, bool C2) {
	return (C1 ? 3 : 0) | (C2 ? 0x18 : 0) | (C1 && C2) << 2;
}

///////////////////////////////////////////////////////////////////////////////

inline ushort CheckNeibPixD(bool C1, bool C2) {
	return (C1 ? 3 : 0) << 9 | (C2 ? 3 : 0) | (C1 && C2) << 11;
}

///////////////////////////////////////////////////////////////////////////////

__kernel void LBEQ2_Init(
	__global const TPixel *pixels, // Image pixels		
	__global TLabel *sLabels,	   // Super labels
	__global char *sConn,	 	   // Super pixels connectivity
	uint w, // Image width
	uint h  // Image height
	)
{
	int spx = get_global_id(0);
	int spy = get_global_id(1);

	size_t spos = spx + spy * ceil((float)w / 2); // Super pixel position
	size_t px = spx * 2, py = spy * 2;
	size_t ppos = px + py * w;

	char conn = 0;

	// 2 3 4 5
	// 1 a b 6
	// 0 d c 7
	// B A 9 8
	ushort testPattern = 0;
	if (pixels[ppos])										testPattern = CheckNeibPixABC(px, py);
	if (px + 1 < w && pixels[ppos + 1])						testPattern |= CheckNeibPixABC(py, px + 2 < w) << 3;
	if (px + 1 < w && py + 1 < h && pixels[ppos + 1 + w])	testPattern |= CheckNeibPixABC(px + 2 < w, py + 2 < h) << 6;
	if (py + 1 < h && pixels[ppos + w])						testPattern |= CheckNeibPixD(py + 2 < h, px);

	if (testPattern) {
		sLabels[spos] = spos + 1;

		if ((testPattern & 1 << 0 && TestBit(pixels, px, py, -1, 1, w, h)) ||
			(testPattern & 1 << 1 && TestBit(pixels, px, py, -1, 0, w, h)))
			conn = 1;
		if ((testPattern & 1 << 2 && TestBit(pixels, px, py, -1, -1, w, h)))
			conn |= 1 << 1;
		if ((testPattern & 1 << 3 && TestBit(pixels, px, py, 0, -1, w, h)) ||
			(testPattern & 1 << 4 && TestBit(pixels, px, py, 1, -1, w, h)))
			conn |= 1 << 2;
		if ((testPattern & 1 << 5 && TestBit(pixels, px, py, 2, -1, w, h)))
			conn |= 1 << 3;
		if ((testPattern & 1 << 6 && TestBit(pixels, px, py, 2, 0, w, h)) ||
			(testPattern & 1 << 7 && TestBit(pixels, px, py, 2, 1, w, h)))
			conn |= 1 << 4;
		if ((testPattern & 1 << 8 && TestBit(pixels, px, py, 2, 2, w, h)))
			conn |= 1 << 5;
		if ((testPattern & 1 << 9 && TestBit(pixels, px, py, 1, 2, w, h)) ||
			(testPattern & 1 << 10 && TestBit(pixels, px, py, 0, 2, w, h)))
			conn |= 1 << 6;
		if ((testPattern & 1 << 11 && TestBit(pixels, px, py, -1, 2, w, h)))
			conn |= 1 << 7;
	}

	sConn[spos] = conn;
}

///////////////////////////////////////////////////////////////////////////////

inline TLabel GetBlockLabel(__global const TLabel *sPix, bool conn, int px, int py,
	int xshift, int yshift, int sWidth)
{
	return conn ? sPix[px + xshift + (py + yshift) * sWidth] : UINT_MAX;
}

///////////////////////////////////////////////////////////////////////////////

TLabel MinSPixLabel(__global const TLabel *sLabels, char conn, int x, int y, int sWidth)
{
	TLabel minLabel;

	minLabel = min(GetBlockLabel(sLabels, conn & 1 << 0, x, y, -1, 0, sWidth),
		min(GetBlockLabel(sLabels, conn & 1 << 1, x, y, -1, -1, sWidth),
		min(GetBlockLabel(sLabels, conn & 1 << 2, x, y, 0, -1, sWidth),
		min(GetBlockLabel(sLabels, conn & 1 << 3, x, y, 1, -1, sWidth),
		min(GetBlockLabel(sLabels, conn & 1 << 4, x, y, 1, 0, sWidth),
		min(GetBlockLabel(sLabels, conn & 1 << 5, x, y, 1, 1, sWidth),
		min(GetBlockLabel(sLabels, conn & 1 << 6, x, y, 0, 1, sWidth),
		GetBlockLabel(sLabels, conn & 1 << 7, x, y, -1, 1, sWidth))))))));

	return minLabel;
}

///////////////////////////////////////////////////////////////////////////////

__kernel void LBEQ2_Scan(
	__global TLabel *sLabels,	// Super labels
	__global char *sConn,		// Super pixels connectivity	
	__global char *noChanges	// Shows if no pixels were changed
	)
{
	const size_t spx = get_global_id(0);
	const size_t spy = get_global_id(1);
	const size_t sWidth = get_global_size(0);
	const size_t spos = spx + spy * sWidth;

	TLabel label = sLabels[spos];
	char conn = sConn[spos];

	if (label) {
		TLabel minLabel = MinSPixLabel(sLabels, conn, spx, spy, sWidth);

		if (minLabel < label) {
			TLabel tmpLabel = sLabels[label - 1];
			sLabels[label - 1] = min(tmpLabel, minLabel);
			*noChanges = 0;
		}
	}
}

///////////////////////////////////////////////////////////////////////////////

__kernel void LBEQ2_Analyze(__global TLabel *sLabels)
{
	const size_t sPos = get_global_id(0);

	TLabel label = sLabels[sPos];

	if (label){
		TLabel curLabel = sLabels[label - 1];
		while (curLabel != label)
		{
			label = sLabels[curLabel - 1];
			curLabel = sLabels[label - 1];
		}

		sLabels[sPos] = label;
	}
}

///////////////////////////////////////////////////////////////////////////////

__kernel void LBEQ2_SetFinalLabels(
	__global TPixel *pixels,
	__global TLabel *labels,
	__global TLabel *sLabels
	)
{
	const size_t x = get_global_id(0);
	const size_t y = get_global_id(1);
	const size_t w = get_global_size(0);
	const size_t spos = (x >> 1) + (y >> 1) * ceil((float)w / 2);
	const size_t pos = x + y * w;

	if (pixels[pos]) {
		labels[pos] = sLabels[spos];
	}
}

///////////////////////////////////////////////////////////////////////////////
// TOCLRunEquivLabeling kernels
///////////////////////////////////////////////////////////////////////////////

// TRun structure:
//                   tl          tr 
//                   v           v
// Top row:      000 0000 000000 000000000 
// Current row:   l -> 00000000000000 <- r
// Bottom row:    0000000000       0000000000
//                ^                ^
//                bl               br  
typedef struct
{
	uint l, r;		// Left and right run positions
} TRunSize;

typedef struct
{
	TLabel lb;		// Run label
	uint l, r;		// Run l and r
	TRunSize top;	// Top row tl and tr
	TRunSize bot;	// Bottom row bl and br
} TRun;

///////////////////////////////////////////////////////////////////////////////

__kernel void REInitRunsKernel(
	__global uint	*runNum	// Image runs
	)
{
	const size_t pos = get_global_id(0);

	runNum[pos] = 0;
}

///////////////////////////////////////////////////////////////////////////////

__kernel void REFindRunsKernel(
	__global TPixel	*pixels,	// Image pixels
	__global TRun	*runs,		// Image runs
	__global uint  *runNum,    // Run count in row
	uint	width		// Image width
	)
{
	const size_t row = get_global_id(0);

	uint pixPos = row * width;
	uint rowPos = row * (width >> 1);

	__global TPixel *curPix = pixels + pixPos;
	__global TRun *curRun = runs + rowPos;

	uint runPos = 0;
	curRun->lb = 0;
	for (uint pos = 0; pos < width; ++pos)
	{
		if (*curPix) {
			if (!curRun->lb) {
				curRun->lb = rowPos + ++runPos;
				curRun->l = pos;
			}
			if (pos == width - 1) {
				curRun->r = pos;
				++curRun;
				curRun->lb = 0;
			}
		}
		else {
			if (curRun->lb) {
				curRun->r = pos - 1;
				++curRun;
				curRun->lb = 0;
			}
		}
		++curPix;
	}
	runNum[row] = runPos;
}

///////////////////////////////////////////////////////////////////////////////

int IsNeib(__global const TRun *r1, __global const TRun *r2)
{
	return
		(r1->l >= r2->l && r1->l <= r2->r) ||
		(r1->r >= r2->l && r1->r <= r2->r) ||
		(r2->r >= r1->l && r2->r <= r1->r) ||
		(r2->r >= r1->l && r2->r <= r1->r);
}

///////////////////////////////////////////////////////////////////////////////

void FindNeibRuns(__global TRun *curRun,
	__global TRunSize *neibSize,
	__global const TRun *neibRow,
	uint *neibPos, uint runWidth)
{
	int noNeib = 0;
	neibSize->l = 1;
	neibSize->r = 0;

	while (*neibPos < runWidth && !noNeib)
	{
		if (IsNeib(curRun, neibRow + *neibPos)) {
			if (neibSize->l > neibSize->r) {
				neibSize->l = neibRow[*neibPos].lb - 1;
			}
			neibSize->r = neibRow[*neibPos].lb - 1;

			if (*neibPos + 1 < runWidth   &&
				neibRow[*neibPos + 1].lb &&
				neibRow[*neibPos + 1].l <= curRun->r)
			{
				++(*neibPos);
			}
			else {
				noNeib = 1;
			}
		}
		else {
			if (neibRow[*neibPos].r < curRun->l) {
				++(*neibPos);
			}
			else {
				noNeib = 1;
			}
		}
	}
}

///////////////////////////////////////////////////////////////////////////////

void FindNeib(__global TRun *curRun,
	__global TRunSize *neibSize,
	__global const TRun *neibRow,
	uint runWidth)
{
	for (uint i = 0; i < runWidth && neibRow[i].lb; ++i)
	{
		if (IsNeib(curRun, neibRow + i)) {
			if (neibSize->l > neibSize->r) {
				neibSize->l = neibRow[i].lb - 1;
			}
			neibSize->r = neibRow[i].lb - 1;
		}
	}
}

///////////////////////////////////////////////////////////////////////////////

__kernel void REFindNeibKernel(
	__global TRun	*runs,	 // Intermediate buffers
	__global uint   *runNum, // Run numer inside a row
	uint	width	 // Image width
	)
{
	const size_t row = get_global_id(0);
	const size_t height = get_global_size(0);

	uint runWidth = width >> 1;

	__global TRun *curRun = runs + row * runWidth;
	const __global TRun *topRow = curRun - runWidth;
	const __global TRun *botRow = curRun + runWidth;

	uint topPos = 0;
	uint botPos = 0;

	for (uint pos = 0; pos < runNum[row]; ++pos)
	{
		if (row > 0) {
			FindNeibRuns(curRun, &curRun->top, topRow, &topPos, runNum[row - 1]);
		}
		else{
			curRun->top.l = 1;
			curRun->top.r = 0;
		}

		if (row < height - 1) {
			FindNeibRuns(curRun, &curRun->bot, botRow, &botPos, runNum[row + 1]);
		}
		else{
			curRun->bot.l = 1;
			curRun->bot.r = 0;
		}

		++curRun;
	}
}

///////////////////////////////////////////////////////////////////////////////

TLabel MinRunLabel(const __global TRun *runs, uint pos)
{
	TLabel minLabel = UINT_MAX;

	if (runs[pos].top.l <= runs[pos].top.r) {
		for (uint i = runs[pos].top.l; i < runs[pos].top.r + 1; ++i) {
			minLabel = min(minLabel, runs[i].lb);
		}
	}

	if (runs[pos].bot.l <= runs[pos].bot.r) {
		for (uint i = runs[pos].bot.l; i < runs[pos].bot.r + 1; ++i) {
			minLabel = min(minLabel, runs[i].lb);
		}
	}

	return minLabel;
}

///////////////////////////////////////////////////////////////////////////////

__kernel void REScanKernel(
	__global TRun	*runs,		// Image runs
	__global uint   *runNum,    // Run count inside a row
	uint	width,		// Image width
	__global char	*noChanges	// Shows if no pixels were changed
	)
{
	const size_t row = get_global_id(0);

	uint runWidth = width >> 1;

	for (int pos = 0; pos < runNum[row]; ++pos)
	{
		TLabel label = runs[row * (width >> 1) + pos].lb;

		if (label)
		{
			TLabel minLabel = MinRunLabel(runs, row * (width >> 1) + pos);

			if (minLabel < label)
			{
				TLabel tmpLabel = runs[label - 1].lb;
				runs[label - 1].lb = min(tmpLabel, minLabel);
				*noChanges = 0;
			}
		}
	}
}

///////////////////////////////////////////////////////////////////////////////

__kernel void REAnalizeKernel(
	__global TRun *runs,
	__global uint *runNum,
	uint width
	)
{
	const size_t row = get_global_id(0);

	for (int pos = 0; pos < runNum[row]; ++pos)
	{
		__global TRun *curRun = &runs[row * (width >> 1) + pos];
		TLabel label = curRun->lb;

		if (label){
			TLabel curLabel = runs[label - 1].lb;
			while (curLabel != label)
			{
				label = runs[curLabel - 1].lb;
				curLabel = runs[label - 1].lb;
			}

			curRun->lb = label;
		}
	}
}

///////////////////////////////////////////////////////////////////////////////

__kernel void RELabelKernel(
	__global TRun	*runs,		// Image runs
	__global uint	*runNum,	// Run count inside a row
	__global TLabel	*labels,	// Image labels
	uint	width		// Image width
	)
{
	const size_t row = get_global_id(0);

	uint runWidth = width >> 1;

	for (int run = 0; run < runNum[row]; ++run)
	{
		TRun curRun = runs[row * (width >> 1) + run];

		if (curRun.lb) {
			for (uint i = curRun.l; i < curRun.r + 1; ++i)
			{
				labels[row * width + i] = curRun.lb;
			}
		}
	}
}

///////////////////////////////////////////////////////////////////////////////
// TOCLBinLabeling3D kernels
///////////////////////////////////////////////////////////////////////////////

__kernel void Bin3D_LabelingKernel(
	__global TPixel	*pixels, // Image pixels
	__global TLabel	*labels	 // Image labels
	)
{
	uint id = get_global_id(0);
	labels[id] = pixels[id] > 0 ? 1 : 0;
}

///////////////////////////////////////////////////////////////////////////////

#endif /* LABELING_ALGS_CL_ */