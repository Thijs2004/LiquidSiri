/liquidSiriPollAudio/,/^}/c\
- (void)liquidSiriPollAudio:(CADisplayLink *)link {\
    id delegate = nil;\
    id objSelf = (id)self;\
    @try {\
        if ([objSelf respondsToSelector:@selector(flamesDelegate)]) {\
            delegate = [objSelf valueForKey:@"flamesDelegate"];\
        } else if ([objSelf respondsToSelector:@selector(delegate)]) {\
            delegate = [objSelf valueForKey:@"delegate"];\
        }\
    } @catch (NSException *e) {}\
\
    if (delegate && [delegate respondsToSelector:@selector(audioLevelForFlamesView:)]) {\
        float level = ((float (*)(id, SEL, id))objc_msgSend)(delegate, @selector(audioLevelForFlamesView:), self);\
        \
        float punchyPower = powf(level * 10.0, 2.0);\
        float finalPower = MIN(2.5, punchyPower * 2.0);\
        \
        sendPowerToSpringBoard(finalPower);\
    }\
}
