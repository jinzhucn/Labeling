#ifndef OCL_COMMONS_CL_
#define OCL_COMMONS_CL_

typedef uchar TPixel;
typedef uint  TLabel;

TPixel GetPixel(__global TPixel *pix, size_t pos, uint maxSize) {
	return pos && pos < maxSize ? pix[pos] : 0;
}

TLabel GetLabel(__global TLabel *labels, size_t pos, uint maxSize) {
	return pos && pos < maxSize ? labels[pos] : 0;
}

TLabel MinLabel(TLabel lb1, TLabel lb2)
{
	if(lb1 && lb2) 
		return min(lb1, lb2);
	
	TLabel lb = max(lb1, lb2);
	
	return lb ? lb : UINT_MAX;
}

TLabel MinNWSELabel(__global TLabel *labels, size_t pos, uint width, uint maxSize)
{
	 return MinLabel(GetLabel(labels, pos -     1, maxSize),
			MinLabel(GetLabel(labels, pos - width, maxSize),
			MinLabel(GetLabel(labels, pos + width, maxSize),
					 GetLabel(labels, pos +     1, maxSize))));
}

#endif /* OCL_COMMONS_CL_ */