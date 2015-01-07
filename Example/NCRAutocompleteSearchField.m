//
//  NCAutocompleteTextView.m
//  Example
//
//  Created by Daniel Weber on 9/28/14.
//  Copyright (c) 2014 Null Creature. All rights reserved.
//

#import "NCRAutocompleteSearchField.h"

#define MAX_RESULTS 10

#define HIGHLIGHT_STROKE_COLOR [NSColor selectedMenuItemColor]
#define HIGHLIGHT_FILL_COLOR [NSColor selectedMenuItemColor]
#define HIGHLIGHT_RADIUS 0.0
#define INTERCELL_SPACING NSMakeSize(20.0, 3.0)

#define WORD_BOUNDARY_CHARS [[NSCharacterSet alphanumericCharacterSet] invertedSet]

#define POPOVER_WIDTH 250.0
#define POPOVER_PADDING 0.0

//#define POPOVER_APPEARANCE NSAppearanceNameVibrantDark
#define POPOVER_APPEARANCE NSAppearanceNameVibrantLight

#define POPOVER_FONT [NSFont fontWithName:@"Menlo" size:12.0]
// The font for the characters that have already been typed
#define POPOVER_BOLDFONT [NSFont fontWithName:@"Menlo-Bold" size:13.0]
#define POPOVER_TEXTCOLOR [NSColor blackColor]

#pragma mark -

@interface NCRAutocompleteTableRowView : NSTableRowView
@end
@implementation NCRAutocompleteTableRowView
- (void)drawSelectionInRect:(NSRect)dirtyRect
{
    if (self.selectionHighlightStyle != NSTableViewSelectionHighlightStyleNone) {
        NSRect selectionRect = NSInsetRect(self.bounds, 0.5, 0.5);
        [HIGHLIGHT_STROKE_COLOR setStroke];
        [HIGHLIGHT_FILL_COLOR setFill];
        NSBezierPath *selectionPath = [NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:HIGHLIGHT_RADIUS yRadius:HIGHLIGHT_RADIUS];
        [selectionPath fill];
        [selectionPath stroke];
    }
}
- (NSBackgroundStyle)interiorBackgroundStyle
{
    if (self.isSelected) {
        return NSBackgroundStyleDark;
    } else {
        return NSBackgroundStyleLight;
    }
}
@end

#pragma mark -

@interface NCRAutocompleteSearchField ()
@property(nonatomic, strong) NSPopover *autocompletePopover;
@property(nonatomic, weak) NSTableView *autocompleteTableView;
@property(nonatomic, strong) NSArray *matches;
// Used to highlight typed characters and insert text
@property(nonatomic, copy) NSString *substring;
// Used to keep track of when the insert cursor has moved so we
// can close the popover. See didChangeSelection:
@property(nonatomic, assign) NSInteger lastPos;
@property(nonatomic, assign) NSRange selectedRange;
@property(nonatomic, strong) NSText *fieldEditor;
@end

@implementation NCRAutocompleteSearchField

- (void)awakeFromNib
{
    // Make a table view with 1 column and enclosing scroll view. It doesn't
    // matter what the frames are here because they are set when the popover
    // is displayed
    NSTableColumn *column1 = [[NSTableColumn alloc] initWithIdentifier:@"text"];
    [column1 setEditable:NO];
    [column1 setWidth:POPOVER_WIDTH - 2 * POPOVER_PADDING];

    NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    [tableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
    [tableView setBackgroundColor:[NSColor clearColor]];
    [tableView setRowSizeStyle:NSTableViewRowSizeStyleSmall];
    [tableView setIntercellSpacing:INTERCELL_SPACING];
    [tableView setHeaderView:nil];
    [tableView setRefusesFirstResponder:YES];
    [tableView setTarget:self];
    [tableView setDoubleAction:@selector(insert:)];
    [tableView addTableColumn:column1];
    [tableView setDelegate:self];
    [tableView setDataSource:self];
    self.autocompleteTableView = tableView;

    NSScrollView *tableScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [tableScrollView setDrawsBackground:NO];
    [tableScrollView setDocumentView:tableView];
    [tableScrollView setHasVerticalScroller:YES];

    NSView *contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    [contentView addSubview:tableScrollView];

    NSViewController *contentViewController = [[NSViewController alloc] init];
    [contentViewController setView:contentView];

    self.autocompletePopover = [[NSPopover alloc] init];
    self.autocompletePopover.appearance = [NSAppearance appearanceNamed:POPOVER_APPEARANCE];
    self.autocompletePopover.animates = NO;
    self.autocompletePopover.contentViewController = contentViewController;

    self.matches = [NSMutableArray array];
    self.lastPos = -1;

    // grab field editor from active window
    NSWindow *mainWindow = [self window];
    [mainWindow makeFirstResponder:self];
    self.fieldEditor = [mainWindow fieldEditor:NO forObject:self];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeSelection:) name:@"NSSearchFieldDidChangeSelectionNotification" object:nil];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    // set selected range
    [self.fieldEditor setSelectedRange:NSMakeRange([[self stringValue] length], 0)];
    self.selectedRange = self.fieldEditor.selectedRange;

    // capture keyboard input
    NSEvent *theEvent = [NSApp currentEvent];
    BOOL shouldComplete = YES;
    
    // handle clicking X in search field
    if (theEvent.type == NSLeftMouseUp) {
        if (self.autocompletePopover.isShown)
            [self.autocompletePopover close];
        return; // Skip default behavior
    }
    switch (theEvent.keyCode) {
    case 51:
        // Delete
        [self.autocompletePopover close];
        shouldComplete = NO;
        break;
    case 53:
        // Esc
        if (self.autocompletePopover.isShown)
            [self.autocompletePopover close];
        return; // Skip default behavior
    case 49:
        // Space
        if (self.autocompletePopover.isShown) {
            [self.autocompletePopover close];
        }
        break;
    }
    if (shouldComplete) {
        [self complete:self];
    }
}

#pragma mark - NSControlTextEditingDelegate
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
    NSInteger row = self.autocompleteTableView.selectedRow;
    if (command == @selector(moveUp:)) {
        if (self.autocompletePopover.isShown) {
            [self.autocompleteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
            [self.autocompleteTableView scrollRowToVisible:self.autocompleteTableView.selectedRow];
            return YES; // Skip default behavior
        }
    } else if (command == @selector(moveDown:)) {
        if (self.autocompletePopover.isShown) {
            [self.autocompleteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
            [self.autocompleteTableView scrollRowToVisible:self.autocompleteTableView.selectedRow];
            return YES; // Skip default behavior
        }
    } else if (((command == @selector(insertNewline:)) || (command == @selector(insertNewlineIgnoringFieldEditor:))) && self.matches.count) {
        if (self.autocompletePopover.isShown) {
            [self insert:self];
            return YES; // Skip default behavior
        }
    } else {
        return NO;
    }
    return NO;
}

- (void)insert:(id)sender
{
    if (self.autocompleteTableView.selectedRow >= 0 && self.autocompleteTableView.selectedRow < self.matches.count) {
        NSString *string = [self.matches objectAtIndex:self.autocompleteTableView.selectedRow];
        self.stringValue = string;
    }
    [self.autocompletePopover close];
}

- (void)didChangeSelection:(NSNotification *)notification
{
    if (labs(self.selectedRange.location - self.lastPos) > 1) {
        // If selection moves by more than just one character, hide autocomplete
        [self.autocompletePopover close];
    }
}

- (void)complete:(id)sender
{
    NSInteger startOfWord = self.selectedRange.location;
    for (NSInteger i = startOfWord - 1; i >= 0; i--) {
        if ([WORD_BOUNDARY_CHARS characterIsMember:[self.stringValue characterAtIndex:i]]) {
            break;
        } else {
            startOfWord--;
        }
    }

    NSInteger lengthOfWord = 0;
    for (NSInteger i = startOfWord; i < self.stringValue.length; i++) {
        if ([WORD_BOUNDARY_CHARS characterIsMember:[self.stringValue characterAtIndex:i]]) {
            break;
        } else {
            lengthOfWord++;
        }
    }

    self.substring = [self.stringValue substringWithRange:NSMakeRange(startOfWord, lengthOfWord)];
    NSRange substringRange = NSMakeRange(startOfWord, self.selectedRange.location - startOfWord);

    if (substringRange.length == 0 || lengthOfWord == 0) {
        // This happens when we just started a new word or if we have already typed the entire word
        [self.autocompletePopover close];
        return;
    }

    NSInteger index = 0;
    self.matches = [self completionsForPartialWordRange:substringRange indexOfSelectedItem:&index];

    if (self.matches.count > 0) {
        self.lastPos = self.selectedRange.location;
        [self.autocompleteTableView reloadData];

        [self.autocompleteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        [self.autocompleteTableView scrollRowToVisible:index];

        // Make the frame for the popover. We want it to shrink with a small number
        // of items to autocomplete but never grow above a certain limit when there
        // are a lot of items. The limit is set by MAX_RESULTS.
        NSInteger numberOfRows = MIN(self.autocompleteTableView.numberOfRows, MAX_RESULTS);
        CGFloat height = (self.autocompleteTableView.rowHeight + self.autocompleteTableView.intercellSpacing.height) * numberOfRows + 2 * POPOVER_PADDING;
        NSRect frame = NSMakeRect(0, 0, POPOVER_WIDTH, height);
        [self.autocompleteTableView.enclosingScrollView setFrame:NSInsetRect(frame, POPOVER_PADDING, POPOVER_PADDING)];
        [self.autocompletePopover setContentSize:NSMakeSize(NSWidth(frame), NSHeight(frame))];

        NSRect searchFieldRect = self.bounds;
        [self.autocompletePopover showRelativeToRect:searchFieldRect ofView:self preferredEdge:NSMaxYEdge];
    } else {
        [self.autocompletePopover close];
    }
}

- (NSArray *)completionsForPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index
{
    if ([self.autocompleteDelegate respondsToSelector:@selector(textField:completions:forPartialWordRange:indexOfSelectedItem:)]) {
        return [self.autocompleteDelegate textField:self completions:@[] forPartialWordRange:charRange indexOfSelectedItem:index];
    }
    return @[];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.matches.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:@"MyView" owner:self];
    if (cellView == nil) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        [textField setBezeled:NO];
        [textField setDrawsBackground:NO];
        [textField setEditable:NO];
        [textField setSelectable:NO];
        [cellView addSubview:textField];
        cellView.textField = textField;
        if ([self.autocompleteDelegate respondsToSelector:@selector(textField:imageForCompletion:)]) {
            NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
            [imageView setImageFrameStyle:NSImageFrameNone];
            [imageView setImageScaling:NSImageScaleNone];
            [cellView addSubview:imageView];
            cellView.imageView = imageView;
        }
        cellView.identifier = @"MyView";
    }

    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:self.matches[row] attributes:@{NSFontAttributeName : POPOVER_FONT, NSForegroundColorAttributeName : POPOVER_TEXTCOLOR}];

    if (self.substring) {
        NSRange range = [as.string rangeOfString:self.substring options:NSAnchoredSearch | NSCaseInsensitiveSearch];
        [as addAttribute:NSFontAttributeName value:POPOVER_BOLDFONT range:range];
    }

    [cellView.textField setAttributedStringValue:as];

    if ([self.autocompleteDelegate respondsToSelector:@selector(textField:imageForCompletion:)]) {
        NSImage *image = [self.autocompleteDelegate textField:self imageForCompletion:self.matches[row]];
        [cellView.imageView setImage:image];
    }

    return cellView;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    return [[NCRAutocompleteTableRowView alloc] init];
}

@end
