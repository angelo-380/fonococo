import SwiftUI
import UIKit

/// Presentation only: completion never advances the authoritative game phase.
public struct CountdownView: UIViewRepresentable {
    public let deadline: Date?
    public init(deadline: Date?) { self.deadline = deadline }
    public func makeUIView(context: Context) -> CountdownUIView { CountdownUIView() }
    public func updateUIView(_ view: CountdownUIView, context: Context) { view.configure(deadline: deadline) }
    public static func dismantleUIView(_ view: CountdownUIView, coordinator: ()) { view.stop() }
}

public final class CountdownUIView: UIView {
    private let label = UILabel()
    private var timer: Timer?
    private var deadline: Date?
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 91/255, green: 200/255, blue: 245/255, alpha: 1)
        layer.cornerRadius = 26
        layer.shadowColor = UIColor(red: 69/255, green: 222/255, blue: 197/255, alpha: 1).cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 5)
        label.textAlignment = .center
        let timerFont = UIFont.systemFont(ofSize: 25, weight: .heavy)
        label.font = UIFont(descriptor: timerFont.fontDescriptor.withDesign(.rounded) ?? timerFont.fontDescriptor, size: 25)
        label.textColor = .white
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor), label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor), label.trailingAnchor.constraint(equalTo: trailingAnchor)])
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    public func configure(deadline: Date?) {
        guard self.deadline != deadline else { return }
        stop()
        self.deadline = deadline
        guard deadline != nil else { label.text = nil; return }
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
    }
    private func update() {
        guard let deadline else { return }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        label.text = "\(seconds)"
        accessibilityLabel = "\(seconds) segundos"
        if seconds == 0 {
            stop()
            UIView.animate(withDuration: 0.2, animations: { [weak self] in self?.label.alpha = 0.5 }) { [weak self] _ in self?.label.alpha = 1 }
        }
    }
    public func stop() { timer?.invalidate(); timer = nil; layer.removeAllAnimations(); label.layer.removeAllAnimations() }
    deinit { timer?.invalidate() }
}
