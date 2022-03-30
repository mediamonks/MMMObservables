# MMMObservables

[![Build](https://github.com/mediamonks/MMMObservables/workflows/Build/badge.svg)](https://github.com/mediamonks/MMMObservables/actions?query=workflow%3ABuild)
[![Test](https://github.com/mediamonks/MMMObservables/workflows/Test/badge.svg)](https://github.com/mediamonks/MMMObservables/actions?query=workflow%3ATest)

Basic support for observers and notifications.

(This is a part of `MMMTemple` suite of iOS libraries we use at [MediaMonks](https://www.mediamonks.com/).)

## Installation

Podfile:

```ruby
source 'https://github.com/mediamonks/MMMSpecs.git'
source 'https://github.com/CocoaPods/Specs.git'
...
pod 'MMMObservables'
```

(Use 'MMMObservables/ObjC' when Swift wrappers are not needed.)

SPM:

```swift
.package(url: "https://github.com/mediamonks/MMMObservables", .upToNextMajor(from: "1.5.0"))
```

## Usage

MMMObservables is a collection of classes to help you track changes in an object where the usual
delegate pattern doesn't fit. Either due to the changes being very simple, or due to the fact that
you can only have a single observer.

### ObserverHub

Helps with implementation of observable objects where you need to ensure that add/remove observer 
functionality works properly. In most cases an array of weak references would work well enough, but 
sometimes tricky cases (like removal of observers while they are being notified) should be handled 
as well.

Please note that the helper is not thread-safe, it handles reentrancy, but makes no assumptions
about threading.

A class using this helper will typically expose its own add/remove observer methods, will forward
their invocation to a private instance of this helper, and will use `forEach` to notify all
the registered observers.

Properties:

- Observers are referenced weakly.
- If an observer is added/removed during a notification cycle, then it won't be called during this cycle.
- Thread-safety (if ever needed) should be handled by the user of the class.

Flags the following conditions in debug builds:

- Observers added more than once.
- Observers not being of reference types (so structs cannot be accidentally installed as observers).
- Observers removed more than once (or tried to be removed without being added first).
- Observers not explicitly removed before their deallocation.
- Nested notification cycles.

> **Note:** Use `MMMObserverHub` if you're using Objective-C. Have a look at `MMMObserverHub.h` for
> more details on that.

**Example:**

```swift

public protocol MyObjectObserverProtocol {
    func didUpdate(object: ChildObject)
    func didRemove(object: ChildObject)
}

public final class MyObject {
    
    private let hub = ObserverHub<MyObjectObserverProtocol>()
    
    private func foo() {
        // We call the methods like you would on a delegate.
        hub.forEach { $0.didUpdate(object: bar) }
        hub.forEach { $0.didRemove(object: baz) }
    }
    
    // Add public functions to add/remove observers so we can keep the `hub` private, otherwise
    // outside users of this class can access the observers, we don't want that.
    public func addObserver(_ observer: MyObjectObserverProtocol) { hub.add(observer) }
    public func removeObserver(_ observer: MyObjectObserverProtocol) { hub.remove(observer) }
}

// The class that observes 'MyObject'.
public final class MyListener: MyObjectObserverProtocol {
    
    private let object = MyObject()
    
    public init() {
        // You can add the observer whenever you want, but only once.
        object.addObserver(self)
    }
    
    deinit {
        // It's required to remove the observer exactly once.
        object.removeObserver(self)
    }
    
    // MARK: - MyObjectObserverProtocol
    
    public func didUpdate(object: ChildObject) {
        ...
    }
    
    public func didRemove(object: ChildObject) {
        ...
    }
}
```

### SimpleEvent

A point where multiple observers can register to be notified when the corresponding object or its 
parts might need attention (aka 'signal', 'event', etc in other libs).

Note that the observers might be notified much later than the actual event happened and multiple
"need attention" events might be combined into one. Use regular observers/delegates in case every
event counts or needs to be reacted upon immediately.

**Example:**

```swift

// In this example we use a ViewModel and Views, but the idiom can be used throughout.
public protocol ViewModel {
    
    // For this example, when this changes, didChange will trigger.
    var title: String { get }
    
    // The 'observable' part, in most cases you only want your users to observe the changes,
    // without the ability to trigger changes from the outside.
    var didChange: SimpleEventObservable { get }
}

public final class DefaultViewModel: ViewModel {
    
    // We use a private `SimpleEvent` and only provide the `SimpleEventObservable` publicly.
    private let _didChange = SimpleEvent()
    public var didChange: SimpleEventObservable { _didChange }
    
    // In this case we trigger the didChange event when the title actually changes.
    public private(set) var title: String = "Initial title" { 
        didSet {
            _didChange.trigger(if: title != oldValue)
        }
    }
    
    ...
    
    private func update() {
        // This will trigger the event.
        title = "Updated title"
        
        // If update() is being re-triggered 'down the line' by this `SimpleEvent`, 
        // it results in nested notifications. This is not allowed by `SimpleEvent`, 
        // look at `LazySimpleEvent` instead.
    }
}

// The 'user' of the ViewModel, a View in this case, but could be anything that's 
// interested in changes in the ViewModel (e.g. ViewController, Flow / Presenter).
internal final class View: UIView {
    
    private let viewModel: ViewModel
    
    // We store the change handler in a token. The token will remove the observer 
    // upon `deinit` or by calling `.remove()`, this ensures that the observer is
    // removed when the view deallocates. 
    private var viewModelDidChange: SimpleEventToken?
    
    ...
    
    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
        
        super.init(frame: .zero)
        
        ...
        
        // Now we can attach a listener to the didChange event to update our UI.
        // 
        // It's critical to store the token, otherwise it will deallocate and 
        // remove the observer straight away.
        viewModel.didChange.addObserver(&viewModelDidChange) { [weak self] _ in
            self?.updateUI()
        }
        
        // You usually want to update your state in any case.
        updateUI()
    }
    
    private func updateUI() {
        // For instance:
        titleLabel.text = viewModel.title
    }
}
```

### LazySimpleEvent + CoalescingCallback

The `CoalescingCallback` coalesces several calls of the same block on the given queue. Handy when 
you need to do a single thing in response to many async events and it does not matter how many of
them or how many times they have occurred.

**Example:**

```swift
// We can specify the queue we should use to handle the events, defaults to `main`.
let callback = CoalescingCallback(queue: DispatchQueue.main) { [weak self] in
    self?.update()
}

if foo {
    callback.schedule()
}

if bar {
    callback.schedule()
}

// If `foo` and `bar` are both `true`, the callback will only execute once, resulting
// in a single call to update().
func update() {
    // Only called once.
}
```

The `LazySimpleEvent` is similar to `SimpleEvent`, however it automatically coalesces all
calls to `trigger()` waking up the observers only once on the next cycle of the given
dispatch queue (main by default).

This way `SimpleEvent`'s `coalescingNotifications()` is not needed here and the issue with
nested calls is automatically avoided.

**Example:**

```swift

class Foo {

    let event = LazySimpleEvent()
    
    public private(set) var foo: String = "a" {
        didSet {
            event.trigger(if: foo != oldValue)
        }
    }
    
    public private(set) var bar: String = "a" {
        didSet {
            event.trigger(if: bar != oldValue)
        }
    }
    
    ...
    
    init() {
        
        // If parent.didChange triggers a change here as well, this would cause nested
        // notifications. Since we're using `LazySimpleEvent` this is no problem.
        parent.didChange.addObserver(&barDidChange) { [weak self] _ in
            self?.update()
        }
    }
    
    private func update() {
        
        // Update get's called from a SimpleEvent, but will handle the nesting gracefully.
        //
        // This is where LazySimpleEvent also comes in handy, we set the values,
        // this triggers multiple calls to the event.trigger(), however, the event
        // will only trigger once.
        
        foo = "b"
        bar = "c"
    }
}
```

### SimpleEventProxy

You pass an array of `SimpleEventObservable`'s and it fires a single event if one of them
fires, it does this lazily.

This fixes the issue where you attach listeners to multiple events only to trigger a single
event (e.g. inside your `ViewModel`); since it inherits from `LazySimpleEvent` you can trigger
the proxy itself as well, this is intentional.

**Example:**

```swift
// Create a private proxy to trigger from 'inside' the model. The simple event
// will trigger when parent & child changes, or if we trigger it ourself.
private lazy var proxy = SimpleEventProxy(events: parent.didChange, child.didChange)

// Change handler for the 'outside'.
public var didChange: SimpleEventObservable { proxy }

private func update() {
    // In case we have changes as well:
    proxy.trigger(if: changed)
}
```

### SimpleEventGroupObserver

You pass an array of `SimpleEventObservable`'s and it listens to them all.

It will collect all events that occur and forward them to a single callback. If you supply
a `debounceTimeout` it will also debounce events. You can supply a specific policy for
the debounce method.

**Debounce Policy:**
 - `default` will reset the timer every time one of the events trigger;
 - `debounceLeading` will trigger the first time, but will ignore all future triggers for the duration of `debounceTimeout`;
 - `throttle` will trigger events at most every `debounceTimeout` seconds.

**Example:**
```swift
let observer = SimpleEventGroupObserver(events: event1, event2, event3) { _ in
    // If any of the events trigger at the same time, we get only a single callback.
}

let debounceObserver = SimpleEventGroupObserver(
    events: event1, event2, event3,
    debounceTimeout: 0.1,
    debouncePolicy: .throttle
) { _ in
    // It doesn't matter how often the events trigger, this callback will be called
    // at most every 0.1 seconds.
}
```

### SimpleMailbox

A box where somebody can put a value replacing whatever was there before, and somebody 
else can later check it and/or take it with them. (Essentially a non-blocking, 
non-thread-safe queue of 1 element.)

Change notifications are performed via an event owned by the object hosting the mailbox.

This is one more step towards avoid unbounded queued events in the app. Using a mailbox
allows to act on certain events a bit later than they were emitted.

**Example:**

```swift

// Something that provides and populates the mailbox.
class Foo {
    
    private let _didChange = LazySimpleEvent()
    public var didChange: SimpleEventObservable { _didChange }
    
    // Initialise your mailbox, using lazy here so we can access `self._didChange`.
    public private(set) lazy var mailbox = SimpleMailbox<Bar>(event: _didChange)
    
    ...
    
    private func update() {
        // Let's place something in the mailbox, someone else should process `Bar`.
        mailbox.placeIfFits(Bar())
    }
}

// Something that acts on the mail being received.
class Listener {
    
    private let foo = Foo()
    private var fooDidChange: SimpleEventToken?
    
    private func observeFoo() {
        
        // We listen to changes using the didChange event.
        foo.didChange.addObserver(&fooDidChange) { [weak self] _ in
            self?.update()
        }
    }
    
    private func update() {
        
        // Now we can check if Foo left us something in the mailbox, if so; we take it!
        if let bar = foo.mailbox.take() {
            // Great, we have a message, do something with `bar`.
        }
    }
}
```

## Ready for liftoff? 🚀

We're always looking for talent. Join one of the fastest-growing rocket ships in
the business. Head over to our [careers page](https://media.monks.com/careers)
for more info!
