import SwiftUI
import UIKit

public final class HistoryViewController: UITableViewController {
    @IBOutlet public weak var historyTable: UITableView?
    public var albums: [ArchivedAlbum] = [] { didSet { if isViewLoaded { tableView.reloadData() } } }
    public override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        navigationController?.navigationBar.tintColor = UIColor(red: 1, green: 0.34, blue: 0.08, alpha: 1)
        historyTable = tableView
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Album")
    }
    @IBAction public func refreshHistory(_ sender: Any?) { tableView.reloadData() }
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { albums.count }
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Album", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = albums[indexPath.row].title
        let rowFont = UIFont.systemFont(ofSize: 17, weight: .bold)
        content.textProperties.font = UIFont(descriptor: rowFont.fontDescriptor.withDesign(.rounded) ?? rowFont.fontDescriptor, size: 17)
        cell.contentConfiguration = content
        cell.backgroundColor = UIColor.white.withAlphaComponent(0.68)
        return cell
    }
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard albums.indices.contains(indexPath.row) else { return }
        let album = albums[indexPath.row]
        let detail = UIHostingController(rootView: Text(album.title))
        let segue = AlbumDetailSegue(identifier: "ShowAlbum", source: self, destination: detail)
        prepare(for: segue, sender: album)
        segue.perform()
    }
}

private final class AlbumDetailSegue: UIStoryboardSegue {
    override func perform() {
        if let navigation = source.navigationController { navigation.pushViewController(destination, animated: true) }
        else { source.present(destination, animated: true) }
    }
}

public struct HistoryControllerView: UIViewControllerRepresentable {
    public var albums: [ArchivedAlbum]
    public init(albums: [ArchivedAlbum]) { self.albums = albums }
    public func makeUIViewController(context: Context) -> UINavigationController {
        let controller = HistoryViewController(style: .plain)
        controller.albums = albums
        return UINavigationController(rootViewController: controller)
    }
    public func updateUIViewController(_ controller: UINavigationController, context: Context) {
        (controller.viewControllers.first as? HistoryViewController)?.albums = albums
    }
}
