#import "FPDocumentView.h"
#import "FPToolPaletteController.h"
#import "FPGraphic.h"

@implementation FPDocumentView

// Draw this many pixels around each page. used for the shadow
static const float PageBorderSize = 10.0;
static const float ZoomScaleFactor = 1.3;

- (NSSize)sizeForPage:(unsigned int)page
{
    PDFPage *pg = [_pdf_document pageAtIndex:page];
    NSSize ret = [pg boundsForBox:_box].size;
    ret.width *= _scale_factor;
    ret.height *= _scale_factor;
    return ret;
}

- (NSRect)frame
{
    if (nil == _pdf_document) {
        NSLog(@"small frame\n");
        return NSMakeRect(0.0, 0.0, 10.0, 10.0);
    }
    NSRect ret = NSMakeRect(0.0, 0.0, 0.0, 0.0);
    for (unsigned int i = 0; i < [_pdf_document pageCount]; i++) {
        NSSize sz = [self sizeForPage:i];
        if (sz.width > NSWidth(ret))
            ret.size.width = sz.width;
        ret.size.height += sz.height + PageBorderSize;
    }
    ret.size.width += 2.0 * PageBorderSize;
    ret.size.height += PageBorderSize;
    return ret;
}

- (FPDocumentView *)printableCopy
{
    FPDocumentView *ret = [[FPDocumentView alloc] initWithFrame:[self frame]];
    ret->_pdf_document = nil;
    ret->_box = _box;
    ret->_scale_factor = _scale_factor;
    ret->_draws_shadow = NO;
    ret->_overlayGraphics = [_overlayGraphics retain];
    ret->_selectedGraphics = [[NSMutableSet alloc] initWithCapacity:0];
    if (_editingGraphic) {
        [_editingGraphic stopEditing];
        _editingGraphic = nil;
    }
    ret->_editingGraphic = nil;
    [ret setPDFDocument:_pdf_document];
    return ret;
}

- (void)initMemberVariables
{
    _pdf_document = nil;
    _box = //kPDFDisplayBoxCropBox;
    _box = kPDFDisplayBoxMediaBox;
    _scale_factor = 1.0;
    _draws_shadow = YES;

    _overlayGraphics = [[NSMutableArray alloc] initWithCapacity:1];
    _selectedGraphics = [[NSMutableSet alloc] initWithCapacity:1];
    _editingGraphic = nil;
}

- (void)dealloc {
    [_pdf_document release];
    [_selectedGraphics release];
    [_overlayGraphics release];
    [super dealloc];
}

- (id)initWithFrame:(NSRect)frameRect
{
    NSLog(@"init w/ frame: %@\n", NSStringFromRect(frameRect));
    frameRect = [self frame];
    if ((self = [super initWithFrame:frameRect]) != nil) {
        // Add initialization code here
        [self initMemberVariables];
    }
    return self;
}

- (void)awakeFromNib
{
    [self initMemberVariables];
}

- (void)setPDFDocument:(PDFDocument *)pdf_document
{
    [_pdf_document release];
    _pdf_document = [pdf_document retain];
    NSLog(@"set pdf doc\n");
    [self setFrame:[self frame]];
    [self setNeedsDisplay:YES];
}

- (void)zoomIn:(id)sender
{
    _scale_factor *= ZoomScaleFactor;
    [self setFrame:[self frame]];
    [self setNeedsDisplay:YES];
    if (_editingGraphic)
        [_editingGraphic documentDidZoom];
}

- (void)zoomOut:(id)sender
{
    _scale_factor /= ZoomScaleFactor;
    [self setFrame:[self frame]];
    [self setNeedsDisplay:YES];
    if (_editingGraphic)
        [_editingGraphic documentDidZoom];
}

- (float)scaleFactor
{
    return _scale_factor;
}

- (void)keyDown:(NSEvent *)theEvent
{
    NSLog(@"got keys: [%@]\n", [theEvent charactersIgnoringModifiers]);
}

- (void)drawRect:(NSRect)rect
{
    NSGraphicsContext* theContext = [NSGraphicsContext currentContext];
    NSLog(@"draw rect\n");

    // draw background
    [[NSColor grayColor] set];
    NSRectFill([self frame]);
    if (nil == _pdf_document) return;
    
    // draw the shadow and white page backgrounds, and pdf pages
    float how_far_down = PageBorderSize;
    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    [shadow setShadowColor:[NSColor blackColor]];
    [shadow setShadowBlurRadius:5.0];
    [shadow setShadowOffset:NSMakeSize(0.0, -2.0)];
    for (unsigned int i = 0; i < [_pdf_document pageCount]; i++) {
        NSSize sz = [self sizeForPage:i];
        NSRect page_rect = NSMakeRect(PageBorderSize, how_far_down,
                                      sz.width, sz.height);
        if (!NSIntersectsRect(rect, page_rect)) goto loop_end;
        if (_draws_shadow) {
            [theContext saveGraphicsState]; // for the shadow
            [shadow set];
        }
        [[NSColor whiteColor] set];
        NSRectFill(page_rect);
        if (_draws_shadow)
            [theContext restoreGraphicsState];
        
        [NSGraphicsContext saveGraphicsState]; // for the clipping rect
        NSRectClip(page_rect);
        
        NSAffineTransform *at = [self transformForPage:i];
//        NSAffineTransform *at = [NSAffineTransform transform];
//        [at scaleXBy:1.0 yBy:(-1.0)];
//        [at translateXBy:PageBorderSize yBy:(-1.0*(how_far_down + NSHeight(page_rect)))];
//        [at scaleXBy:_scale_factor yBy:_scale_factor];
        [at concat];
        [[_pdf_document pageAtIndex:i] drawWithBox:_box];

        for (unsigned int j = 0; j < [_overlayGraphics count]; j++) {
            FPGraphic *g;
            g = [_overlayGraphics objectAtIndex:j];
            if ([g page] == i)
                [g draw];
        }
        for (unsigned int j = 0; j < [_overlayGraphics count]; j++) {
            FPGraphic *g;
            g = [_overlayGraphics objectAtIndex:j];
            if ([g page] == i && [_selectedGraphics containsObject:g])
                [g drawKnobs];
        }

        [at invert];
        [at concat];
        [NSGraphicsContext restoreGraphicsState]; // undo page clipping rect
      loop_end:
        how_far_down += NSHeight(page_rect) + PageBorderSize;
    }
}

- (unsigned int)pageForPointFromEvent:(NSEvent *)theEvent
{
    NSPoint loc_in_window = [theEvent locationInWindow];
    loc_in_window.x += 0.5;
    loc_in_window.y -= 0.5; // correct for coordinates being between pixels
    NSPoint loc_in_view = [[[self window] contentView] convertPoint:loc_in_window toView:self];

    if (nil == _pdf_document) return 0;
    float bottom_border = PageBorderSize / 2.0;
    for (unsigned int i = 0; i < [_pdf_document pageCount]; i++) {
        NSSize sz = [self sizeForPage:i];
        bottom_border += sz.height + PageBorderSize;
        if (loc_in_view.y < bottom_border) return i;
    }
    return [_pdf_document pageCount] - 1;
}

// thre returned transform works in the following direction:
// page-coordinate ==(transform)==> doc-view-coordinate
- (NSAffineTransform *)transformForPage:(unsigned int)page
{
    assert(_pdf_document);
    assert(page < [_pdf_document pageCount]);

    NSAffineTransform *at = [NSAffineTransform transform];
    [at scaleXBy:1.0 yBy:-1.0];
    float yTranslate = 0.0;
    for (unsigned int i = 0; i <= page; i++) {
        NSSize sz = [self sizeForPage:i];
        yTranslate -= (PageBorderSize + sz.height);
    }
    [at translateXBy:PageBorderSize yBy:yTranslate];
    [at scaleXBy:_scale_factor yBy:_scale_factor];
    return at;
}

- (NSPoint)convertPoint:(NSPoint)point toPage:(unsigned int)page
{
    NSAffineTransform *transform = [self transformForPage:page];
    [transform invert];
    return [transform transformPoint:point];
}

- (NSPoint)convertPoint:(NSPoint)point fromPage:(unsigned int)page
{
    NSAffineTransform *transform = [self transformForPage:page];
    return [transform transformPoint:point];
}

- (NSRect)convertRect:(NSRect)rect toPage:(unsigned int)page
{
    assert(rect.size.width >= 0.0);
    assert(rect.size.height >= 0.0);
    NSPoint bottomLeft = NSMakePoint(NSMinX(rect), NSMaxY(rect));
    NSPoint upperRight = NSMakePoint(NSMaxX(rect), NSMinY(rect));
    NSPoint newBottomLeft = [self convertPoint:bottomLeft toPage:page];
    NSPoint newUpperRight = [self convertPoint:upperRight toPage:page];
    NSRect ret;
    ret.origin = newBottomLeft;
    ret.size = NSMakeSize(newUpperRight.x - newBottomLeft.x, newUpperRight.y - newBottomLeft.y);
    assert(ret.size.width >= 0.0);
    assert(ret.size.height >= 0.0);
    return ret;
}

- (NSRect)convertRect:(NSRect)rect fromPage:(unsigned int)page
{
    assert(rect.size.width >= 0.0);
    assert(rect.size.height >= 0.0);
    NSPoint bottomLeft = rect.origin;
    NSPoint upperRight = NSMakePoint(NSMaxX(rect), NSMaxY(rect));
    NSPoint newBottomLeft = [self convertPoint:bottomLeft fromPage:page];
    NSPoint newUpperRight = [self convertPoint:upperRight fromPage:page];
    NSRect ret;
    ret.origin.x = newBottomLeft.x;
    ret.origin.y = newUpperRight.y;
    ret.size.width = newUpperRight.x - newBottomLeft.x;
    ret.size.height = newBottomLeft.y - newUpperRight.y;
    assert(ret.size.width >= 0.0);
    assert(ret.size.height >= 0.0);
    return ret;
}

- (NSPoint)pagePointForPointFromEvent:(NSEvent *)theEvent page:(unsigned int)page
{
    NSPoint loc_in_window = [theEvent locationInWindow];
    loc_in_window.x += 0.5;
    loc_in_window.y -= 0.5; // correct for coordinates being between pixels
    NSPoint loc_in_view = [[[self window] contentView] convertPoint:loc_in_window toView:self];
    NSPoint loc_in_page = [self convertPoint:loc_in_view toPage:page];
    return loc_in_page;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)moveSelectionWithEvent:(NSEvent *)theEvent
{
    NSPoint oldPoint;
    NSPoint newPoint;
    float deltaX, deltaY;
    unsigned int oldPage;
    unsigned int newPage;
    int i;
    
    NSArray *selectedGraphics = [_selectedGraphics allObjects];
    
    oldPage = [self pageForPointFromEvent:theEvent];
    oldPoint = [self pagePointForPointFromEvent:theEvent page:oldPage];
    
    for (;;) {
        // get ready for next iteration of the loop, or break out of loop
        theEvent = [[self window] nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
        if ([theEvent type] == NSLeftMouseUp)
            break;
        
        // main loop body
        newPage = [self pageForPointFromEvent:theEvent];
        if (newPage != oldPage) {
            for (i = 0; i < [selectedGraphics count]; i++) {
                FPGraphic *g = [selectedGraphics objectAtIndex:i];
                [self setNeedsDisplayInRect:[self convertRect:[g boundsWithKnobs] fromPage:[g page]]];
                [g reassignToPage:newPage];
                [self setNeedsDisplayInRect:[self convertRect:[g boundsWithKnobs] fromPage:[g page]]];
            }
            // reassign oldPoint to the newPage
            oldPoint = [self convertPoint:[self convertPoint:oldPoint fromPage:oldPage] toPage:newPage];
            oldPage = newPage;
        }

        newPoint = [self pagePointForPointFromEvent:theEvent
                                               page:oldPage];
        
        deltaX = newPoint.x - oldPoint.x;
        deltaY = newPoint.y - oldPoint.y;
        
        // move the graphics. invalide view for before and after positions
        for (i = 0; i < [selectedGraphics count]; i++) {
            FPGraphic *g = [selectedGraphics objectAtIndex:i];
            [self setNeedsDisplayInRect:[self convertRect:[g boundsWithKnobs] fromPage:[g page]]];
            [g moveGraphicByX:deltaX byY:deltaY];
            [self setNeedsDisplayInRect:[self convertRect:[g boundsWithKnobs] fromPage:[g page]]];
        }
        
        oldPoint = newPoint;
    }
}

- (void)mouseDown:(NSEvent *)theEvent
{
    FPGraphic *graphic;
    BOOL keep;
    unsigned int tool = [[FPToolPaletteController sharedToolPaletteController] currentTool];
    BOOL justStoppedEditing = NO;

    if (_editingGraphic) {
        [_editingGraphic stopEditing];
        assert([_selectedGraphics count] == 0);
        [_selectedGraphics addObject:_editingGraphic];
        _editingGraphic = nil;
        justStoppedEditing = YES;
    }
    
    if (tool == FPToolArrow) {
        int i;
        NSPoint point;
        
        // if we hit a knob, resize that shape by its knob
        if ([_selectedGraphics count]) {
            for (i = [_overlayGraphics count] - 1; i >= 0; i--) {
                graphic = [_overlayGraphics objectAtIndex:i];
                if (![_selectedGraphics containsObject:graphic]) continue;
                int knob = [graphic knobForEvent:theEvent];
                if (knob != NoKnob) {
                    [_selectedGraphics removeAllObjects];
                    [_selectedGraphics addObject:graphic];
                    [self setNeedsDisplay:YES]; // to fix which knobs are showing
                    [graphic resizeWithEvent:theEvent byKnob:knob];
                    return;
                }
            }
        }
        
        // if we hit a shape, then:
        // if holding shift: add or remove shape from selection
        // if not holding shift:
        //   if shape is selected, do nothing
        //   else make shape the only selected shape
        for (i = [_overlayGraphics count] - 1; i >= 0; i--) {
            graphic = [_overlayGraphics objectAtIndex:i];
            point = [self pagePointForPointFromEvent:theEvent page:[graphic page]];
            if (NSPointInRect(point, [graphic safeBounds])) {
                if ([theEvent modifierFlags] & NSShiftKeyMask) {
                    if ([_selectedGraphics containsObject:graphic])
                        [_selectedGraphics removeObject:graphic];
                    else
                        [_selectedGraphics addObject:graphic];
                } else {
                    if ([theEvent clickCount] == 2) {
                        if ([graphic isEditable]) {
                            assert(nil == _editingGraphic);
                            _editingGraphic = graphic;
                            [_selectedGraphics removeAllObjects];
                            [graphic startEditing];
                        }
                    } else if (![_selectedGraphics containsObject:graphic]) {
                        [_selectedGraphics removeAllObjects];
                        [_selectedGraphics addObject:graphic];
                    }
                }
                break;
            }
        }
        if (i < 0) { // point didn't hit any shape
            // if we just stopped editing a shape, keep that selected, otherwise, select none
            if (justStoppedEditing == NO)
                [_selectedGraphics removeAllObjects];
        }
        if ([_selectedGraphics count]) {
            [self setNeedsDisplay:YES];
            [self moveSelectionWithEvent:theEvent];
        }
        //[self setNeedsDisplayInRect:[graphic knobBounds]];
        [self setNeedsDisplay:YES];
        return;
    }
    
    graphic = [[[FPToolPaletteController sharedToolPaletteController] classForCurrentTool] graphicInDocumentView:self];
    assert(graphic);
    [_overlayGraphics addObject:graphic];
    keep = [graphic placeWithEvent:theEvent];
    if (keep == NO) {
        [_overlayGraphics removeLastObject];
    } else {
        if ([graphic isEditable]) {
            [_selectedGraphics removeAllObjects];
            assert(nil == _editingGraphic);
            _editingGraphic = graphic;
            [graphic startEditing];
            [self setNeedsDisplay:YES];
        }
    }
}

/*
static NSTextView *newEditor() {
    // This method returns an NSTextView whose NSLayoutManager has a refcount of 1.  It is the caller's responsibility to release the NSLayoutManager.  This function is only for the use of the following method.
    NSLayoutManager *lm = [[NSLayoutManager allocWithZone:NULL] init];
    NSTextContainer *tc = [[NSTextContainer allocWithZone:NULL] initWithContainerSize:NSMakeSize(1.0e6, 1.0e6)];
    NSTextView *tv = [[NSTextView allocWithZone:NULL] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0) textContainer:nil];

    [lm addTextContainer:tc];
    [tc release];

    [tv setTextContainerInset:NSMakeSize(0.0, 0.0)];
    [tv setDrawsBackground:NO];
    [tv setAllowsUndo:YES];
    [tc setTextView:tv];
    [tv release];

    return tv;
}

- (void)mouseDown:(NSEvent *)theEvent
{
    static NSTextView *_editor = nil;
    NSTextStorage *contents = [[NSTextStorage allocWithZone:[self zone]] init];
    NSLog(@"mouse down\n");
    if (_editor == nil) {
        NSLog(@"allocating\n");
        //_editor = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 40.0)];
		//[[_editor textContainer] setLineFragmentPadding:1.0];
        _editor = newEditor();
        assert(_editor);
	}
    [[_editor textContainer] setWidthTracksTextView:NO];
    [[_editor textContainer] setContainerSize:NSMakeSize(300.0, 300.0)];
    [_editor setHorizontallyResizable:YES]; //x
    [_editor setMinSize:NSMakeSize(10.0, 15.0)];
    [_editor setMaxSize:NSMakeSize(1.0e6, 1.0e6)];

    [[_editor textContainer] setHeightTracksTextView:NO];
    [_editor setVerticallyResizable:YES]; //x
	
	//if (_isAutoSized) {
		//[[_editor textContainer] setContainerSize:NSMakeSize(300.0, 300.0)];
	//} else {
	//	[[_editor textContainer] setContainerSize:_bounds.size];
	//}
    [_editor setFrame:NSMakeRect(30,100,10,15)];
    [contents addLayoutManager:[_editor layoutManager]];
    [self addSubview:_editor];
    //[_editor setDelegate:self];
    [[self window] makeFirstResponder:_editor];
}

- (void)textDidChange:(NSNotification *)notification {
    NSSize textSize;
    NSRect myBounds = NSMakeRect(30, 100, 0, 0);
    BOOL fixedWidth = ([[notification object] isHorizontallyResizable] ? NO : YES);
    
    //textSize = [self requiredSize:(fixedWidth ? NSWidth(myBounds) : 1.0e6)];
    textSize = NSMakeSize(800,1000);
    
    if ((textSize.width > myBounds.size.width) || (textSize.height > myBounds.size.height)) {
        [self setBounds:NSMakeRect(myBounds.origin.x, myBounds.origin.y, ((!fixedWidth && (textSize.width > myBounds.size.width)) ? textSize.width : myBounds.size.width), ((textSize.height > myBounds.size.height) ? textSize.height : myBounds.size.height))];
        // MF: For multiple editors we must fix up the others...  but we don't support multiple views of a document yet, and that's the only way we'd ever have the potential for multiple editors.
    }
}
*/

#pragma mark -
#pragma mark Printing Methods

- (BOOL)knowsPageRange:(NSRangePointer)range
{
    range->location = 1;
    range->length = [_pdf_document pageCount];
    NSLog(@"page range: %d,%d\n", range->location, range->length);
    return YES;
}

// indexed from 1, not 0
- (NSRect)rectForPage:(int)page
{
    assert(page >= 1);
    assert(page <= [_pdf_document pageCount]);
    page--; // now indexed from 0
    // PageBorderSize
    NSRect ret;
    ret.size = [self sizeForPage:page];
    ret.origin.x = PageBorderSize;
    ret.origin.y = PageBorderSize;
    for (int i = 0; i < page; i++) {
        ret.origin.y += [self sizeForPage:i].height + PageBorderSize;
    }
    return ret;
}

// for now, we'll scale the document as a whole such that each page will fit in the printer
// sized page, and we'll scale up as much as possible

#define MINF(a, b) (((a) < (b)) ? (a) : (b))

- (void)beginDocument
{
    // first calculate the max page size in the PDF w/o using the scaling factor
    NSSize maxPageSize = NSMakeSize(0.0, 0.0);
    for (unsigned int i = 0; i < [_pdf_document pageCount]; i++) {
        PDFPage *pg = [_pdf_document pageAtIndex:i];
        NSSize sz = [pg boundsForBox:_box].size;
        if (sz.width > maxPageSize.width)
            maxPageSize.width = sz.width;
        if (sz.height > maxPageSize.height)
            maxPageSize.height = sz.height;
    }
    // now, how big is the printed page?
    NSSize printSize = [[NSPrintInfo sharedPrintInfo] paperSize];
    NSLog(@"printSize: %@\nmaxPageSize: %@\n", NSStringFromSize(printSize), NSStringFromSize(maxPageSize));
    // printed page is how many times as big as the pdf?
    float heightRatio =  printSize.height / maxPageSize.height;
    float widthRatio =  printSize.width / maxPageSize.width;
    float maxRatio = MINF(heightRatio, widthRatio);
    _scale_factor = maxRatio;
    [self setFrame:[self frame]];
    [super beginDocument];
}

@end