//
//  RiskyEncountersPositiveVC.swift
//  BT-Tracking
//
//  Created by Naim Ashhab on 07/08/2020.
//  Copyright © 2020 Covid19CZ. All rights reserved.
//

import UIKit
import RxSwift

final class RiskyEncountersPositiveVC: UITableViewController {

    private let viewModel = RiskyEncountersPositiveVM()
    private let disposeBag = DisposeBag()

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        title = viewModel.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeAction))
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let viewController = segue.destination as? RiskyEncountersListVC else { return }

        switch StoryboardSegue.RiskyEncounters(segue) {
        case .mainSymptoms:
            viewController.viewModel = MainSymptomsVM()
        case .preventTransmission:
            viewController.viewModel = PreventTransmissionVM()
        default:
            break
        }
    }

    // MARK: - Actions

    @IBAction private func closeAction() {
        dismiss(animated: true)
    }

    @IBAction private func showPreviousRiskyEncounters(_ sender: Any) {
        perform(segue: StoryboardSegue.RiskyEncounters.previousRiskyEncounters)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = viewModel.sections[indexPath.section]

        switch indexPath.row {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "textCell") ?? UITableViewCell()
            cell.textLabel?.text = item.localizedText
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "buttonCell") ?? UITableViewCell()
            cell.imageView?.image = item.icon.withRenderingMode(.alwaysOriginal)
            cell.textLabel?.text = item.localizedTitle
            return cell
        default:
            return UITableViewCell()
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel.sections[section].localizedSection
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row == 1 else { return }

        switch viewModel.sections[indexPath.section] {
        case .encounter:
            perform(segue: StoryboardSegue.RiskyEncounters.previousRiskyEncounters)
        case .withSymptoms:
            perform(segue: StoryboardSegue.RiskyEncounters.mainSymptoms)
        case .withoutSymptoms:
            perform(segue: StoryboardSegue.RiskyEncounters.preventTransmission)
        }
    }
}
