//
//  NCAutocompleteTextView.h
//  Example
//
//  Created by Daniel Weber on 9/28/14.
//  Copyright (c) 2014 Null Creature. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol NCRAutocompleteTableViewDelegate <NSObject>
@optional
- (NSImage *)textField:(NSTextField *)textField imageForCompletion:(NSString *)word;
- (NSArray *)textField:(NSTextField *)textField completions:(NSArray *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index;
@end

@interface NCRAutocompleteSearchField : NSSearchField <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSControlTextEditingDelegate>

@property(nonatomic, weak) id<NCRAutocompleteTableViewDelegate> autocompleteDelegate;

@end
