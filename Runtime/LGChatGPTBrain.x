#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

@interface AFSpeechRecognized : NSObject
@property (nonatomic, copy) NSString *text;
@end

@interface AFConnection : NSObject
- (void)sendCommand:(id)command errorHandler:(id)handler;
- (void)_sendCommand:(id)command errorHandler:(id)handler;
- (void)cancelSpeech;
@end

@interface SiriUIBackgroundBlurViewController : UIViewController
@property (nonatomic, strong) UILabel *chatGptLabel;
@property (nonatomic, strong) AVSpeechSynthesizer *speechSynthesizer;
@end

static NSString *globalApiKey = @"";
static BOOL chatGptEnabled = NO;
static SiriUIBackgroundBlurViewController *sharedBlurVC = nil;

void LGFetchChatGPTResponse(NSString *query, SiriUIBackgroundBlurViewController *vc) {
    if (!globalApiKey || globalApiKey.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            vc.chatGptLabel.text = @"ChatGPT API Key is missing. Please configure it in Settings.";
            AVSpeechSynthesizer *synth = [[AVSpeechSynthesizer alloc] init];
            AVSpeechUtterance *utter = [AVSpeechUtterance speechUtteranceWithString:@"API Key is missing."];
            [synth speakUtterance:utter];
        });
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        vc.chatGptLabel.text = @"Thinking...";
    });

    NSDictionary *payload = @{
        @"model": @"gpt-4o",
        @"messages": @[
            @{@"role": @"system", @"content": @"You are a helpful and concise Siri assistant replacement on an iPhone."},
            @{@"role": @"user", @"content": query}
        ]
    };

    NSError *err;
    NSData *postData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&err];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.openai.com/v1/chat/completions"]];
    [req setHTTPMethod:@"POST"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", globalApiKey] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setHTTPBody:postData];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                vc.chatGptLabel.text = @"Network error connecting to ChatGPT.";
            });
            return;
        }
        
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *reply = json[@"choices"][0][@"message"][@"content"];
        if (!reply) {
            reply = @"I could not understand the response from ChatGPT.";
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            vc.chatGptLabel.text = reply;
            
            if (!vc.speechSynthesizer) {
                vc.speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
            }
            AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:reply];
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate;
            [vc.speechSynthesizer speakUtterance:utterance];
        });
    }];
    [task resume];
}

%hook SiriUIBackgroundBlurViewController
%property (nonatomic, strong) UILabel *chatGptLabel;
%property (nonatomic, strong) AVSpeechSynthesizer *speechSynthesizer;

- (void)viewDidLoad {
    %orig;
    sharedBlurVC = self;
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
    if (!prefs) prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist"];
    
    chatGptEnabled = [prefs[@"chatGptEnabled"] boolValue];
    globalApiKey = prefs[@"chatGptApiKey"] ?: @"";
    
    if (chatGptEnabled) {
        self.chatGptLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 150, self.view.bounds.size.width - 40, self.view.bounds.size.height - 300)];
        self.chatGptLabel.textColor = [UIColor whiteColor];
        self.chatGptLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightMedium];
        self.chatGptLabel.numberOfLines = 0;
        self.chatGptLabel.textAlignment = NSTextAlignmentCenter;
        self.chatGptLabel.shadowColor = [UIColor blackColor];
        self.chatGptLabel.shadowOffset = CGSizeMake(0, 1);
        [self.view addSubview:self.chatGptLabel];
    }
}
%end

%hook AFConnection

- (void)sendCommand:(id)command errorHandler:(id)handler {
    if (chatGptEnabled && [command isKindOfClass:NSClassFromString(@"AFSpeechRecognized")]) {
        AFSpeechRecognized *rec = (AFSpeechRecognized *)command;
        NSString *text = [rec text];
        
        if (text && text.length > 0 && sharedBlurVC) {
            // Cancel native Siri processing
            [self cancelSpeech];
            
            // Route to ChatGPT
            LGFetchChatGPTResponse(text, sharedBlurVC);
            
            // Do not call %orig so Apple's servers do not process the command
            return;
        }
    }
    %orig;
}

- (void)_sendCommand:(id)command errorHandler:(id)handler {
    if (chatGptEnabled && [command isKindOfClass:NSClassFromString(@"AFSpeechRecognized")]) {
        AFSpeechRecognized *rec = (AFSpeechRecognized *)command;
        NSString *text = [rec text];
        
        if (text && text.length > 0 && sharedBlurVC) {
            [self cancelSpeech];
            LGFetchChatGPTResponse(text, sharedBlurVC);
            return;
        }
    }
    %orig;
}

%end
