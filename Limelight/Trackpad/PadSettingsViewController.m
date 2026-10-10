//
//  PadSettingsViewController.m
//  iMoonlight
//

#import "PadSettingsViewController.h"
#import "PadSettings.h"
#import "PadHaptics.h"

enum { SectionTrackpad, SectionLayout, SectionKeyboard, SectionHaptics, SectionCount };

/// A row: a slider or a switch bound to a setting.
@interface PadSettingRow : NSObject
@property (nonatomic, copy) NSString* title;
@property (nonatomic, copy, nullable) NSString* detail;
@property (nonatomic, copy) NSString* key;
@property (nonatomic) BOOL isSwitch;
@property (nonatomic) float min, max;
@end

@implementation PadSettingRow
+ (instancetype)slider:(NSString*)title key:(NSString*)key min:(float)min max:(float)max {
    PadSettingRow* r = [[PadSettingRow alloc] init];
    r.title = title;
    r.key = key;
    r.min = min;
    r.max = max;
    return r;
}
+ (instancetype)toggle:(NSString*)title detail:(NSString*)detail key:(NSString*)key {
    PadSettingRow* r = [[PadSettingRow alloc] init];
    r.title = title;
    r.detail = detail;
    r.key = key;
    r.isSwitch = YES;
    return r;
}
@end

@implementation PadSettingsViewController {
    NSArray<NSArray<PadSettingRow*>*>* _rows;
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Trackpad settings";
        _rows = @[
            @[[PadSettingRow slider:@"Pointer speed" key:PadKeySensitivity min:0.5 max:5],
              [PadSettingRow slider:@"Pointer acceleration" key:PadKeyAcceleration min:0 max:2],
              [PadSettingRow slider:@"Scroll speed" key:PadKeyScrollSpeed min:0.5 max:5],
              [PadSettingRow slider:@"Pinch zoom speed" key:PadKeyZoomSpeed min:0.2 max:3],
              [PadSettingRow toggle:@"Classic scroll direction" detail:@"Fingers down scrolls down, like a mouse wheel" key:PadKeyInvertScroll]],
            @[[PadSettingRow toggle:@"Swap screens" detail:@"Trackpad on top, stream underneath" key:PadKeySwapScreens],
              [PadSettingRow toggle:@"Dim when idle" detail:@"After 30 seconds without a touch the trackpad dims; the next touch only wakes it" key:PadKeyDimWhenIdle]],
            @[[PadSettingRow toggle:@"Autocorrect" detail:@"Fixes misspelled and run-together words when you finish them. Tap the suggestion to keep your spelling" key:PadKeyAutocorrect],
              [PadSettingRow toggle:@"Auto-capitalization" detail:@"Capital letter at the start of each sentence" key:PadKeyAutoCapitalize],
              [PadSettingRow toggle:@"\".\" shortcut" detail:@"Tapping space twice types a period and a space" key:PadKeyDoubleSpacePeriod],
              [PadSettingRow toggle:@"Type when the finger lifts" detail:@"Lets you slide onto the right key before it types" key:PadKeyTypeOnRelease]],
            @[],
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self action:@selector(done)];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
}

- (void)done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return SectionCount;
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SectionTrackpad: return @"Trackpad";
        case SectionLayout: return @"Screen";
        case SectionKeyboard: return @"Keyboard";
        default: return @"Haptics";
    }
}

- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
    if (section == SectionHaptics) {
        return @"Each action gets its own feel and strength. Every change plays a preview.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return section == SectionHaptics ? PadHapticActionCount : _rows[section].count;
}

static UILabel* label(NSString* text, UIFont* font, UIColor* color) {
    UILabel* l = [[UILabel alloc] init];
    l.text = text;
    l.font = font;
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    // Rows are few, so each is built fresh: no reuse bookkeeping for the bound controls.
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIStackView* stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
    ]];

    if (indexPath.section == SectionHaptics) {
        [self buildHapticRow:(PadHapticAction)indexPath.row inStack:stack];
        return cell;
    }

    PadSettingRow* row = _rows[indexPath.section][indexPath.row];
    if (row.isSwitch) {
        UIStackView* line = [[UIStackView alloc] init];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.alignment = UIStackViewAlignmentCenter;
        line.spacing = 12;
        UIStackView* texts = [[UIStackView alloc] init];
        texts.axis = UILayoutConstraintAxisVertical;
        texts.spacing = 2;
        [texts addArrangedSubview:label(row.title, [UIFont systemFontOfSize:17], [UIColor labelColor])];
        if (row.detail != nil) {
            [texts addArrangedSubview:label(row.detail, [UIFont systemFontOfSize:13], [UIColor secondaryLabelColor])];
        }
        [line addArrangedSubview:texts];
        UISwitch* toggle = [[UISwitch alloc] init];
        toggle.on = [PadSettings boolForKey:row.key];
        [toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        NSString* key = row.key;
        [toggle addAction:[UIAction actionWithHandler:^(UIAction* action) {
            [PadSettings setBool:((UISwitch*)action.sender).on forKey:key];
        }] forControlEvents:UIControlEventValueChanged];
        [line addArrangedSubview:toggle];
        [stack addArrangedSubview:line];
    } else {
        UILabel* title = label(@"", [UIFont systemFontOfSize:17], [UIColor labelColor]);
        NSString* name = row.title;
        void (^updateTitle)(float) = ^(float v) {
            title.text = [NSString stringWithFormat:@"%@: %.1f", name, v];
        };
        float value = [PadSettings floatForKey:row.key];
        updateTitle(value);
        [stack addArrangedSubview:title];
        UISlider* slider = [[UISlider alloc] init];
        slider.minimumValue = row.min;
        slider.maximumValue = row.max;
        slider.value = value;
        NSString* key = row.key;
        [slider addAction:[UIAction actionWithHandler:^(UIAction* action) {
            float v = roundf(((UISlider*)action.sender).value * 10) / 10;
            updateTitle(v);
            [PadSettings setFloat:v forKey:key];
        }] forControlEvents:UIControlEventValueChanged];
        [stack addArrangedSubview:slider];
    }
    return cell;
}

- (void)buildHapticRow:(PadHapticAction)action inStack:(UIStackView*)stack {
    UIStackView* line = [[UIStackView alloc] init];
    line.axis = UILayoutConstraintAxisHorizontal;
    line.alignment = UIStackViewAlignmentCenter;
    [line addArrangedSubview:label([PadHaptics nameForAction:action], [UIFont systemFontOfSize:17], [UIColor labelColor])];

    UIButton* feelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    feelButton.showsMenuAsPrimaryAction = YES;
    [feelButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [line addArrangedSubview:feelButton];
    [stack addArrangedSubview:line];

    UISlider* strength = [[UISlider alloc] init];
    strength.minimumValue = 0;
    strength.maximumValue = 100;
    strength.value = [PadHaptics strengthForAction:action];
    [strength addAction:[UIAction actionWithHandler:^(UIAction* a) {
        [PadHaptics setStrength:lroundf(((UISlider*)a.sender).value) forAction:action];
    }] forControlEvents:UIControlEventValueChanged];
    // Preview once the finger lets go, rather than on every step.
    [strength addAction:[UIAction actionWithHandler:^(UIAction* a) {
        [PadHaptics play:action];
    }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [stack addArrangedSubview:strength];

    [self refreshFeelButton:feelButton strength:strength action:action];
}

/// Shows the action's current feel on its button, with a menu to pick another.
- (void)refreshFeelButton:(UIButton*)button strength:(UISlider*)strength action:(PadHapticAction)action {
    PadHapticFeel current = [PadHaptics feelForAction:action];
    [button setTitle:[[PadHaptics nameForFeel:current] stringByAppendingString:@" ▾"] forState:UIControlStateNormal];
    strength.enabled = current != PadFeelOff;
    __weak PadSettingsViewController* weakSelf = self;
    __weak UIButton* weakButton = button;
    __weak UISlider* weakStrength = strength;
    NSMutableArray<UIAction*>* items = [NSMutableArray array];
    for (NSInteger f = 0; f < PadFeelCount; f++) {
        UIAction* item = [UIAction actionWithTitle:[PadHaptics nameForFeel:(PadHapticFeel)f] image:nil identifier:nil
                                           handler:^(UIAction* a) {
            [PadHaptics setFeel:(PadHapticFeel)f forAction:action];
            [PadHaptics play:action];
            if (weakButton != nil && weakStrength != nil) {
                [weakSelf refreshFeelButton:weakButton strength:weakStrength action:action];
            }
        }];
        item.state = f == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:item];
    }
    button.menu = [UIMenu menuWithTitle:@"" children:items];
}

@end
